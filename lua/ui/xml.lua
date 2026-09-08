--[[
  ui/xml.lua — cross-platform XML template renderer.

  Usage:
    local xml = require("ui.xml")
    local view = xml.render(xmlString, data, ns)

  The `ns` argument is the platform module (AppKit or UIKit). When omitted,
  require("AppKit") is used.  This lets the same XML file produce NSText on
  macOS or UILabel on iOS without any conditionals in the template.

  Workflow for file-based templates:
    local view = xml.renderFile("examples/mail/views/MailRow.etlua", rowData, ns)

  etlua is applied to the XML source before parsing, so you can embed data
  with <%= expr %> or execute logic with <% if cond then %> ... <% end %>.

  Tag-to-component mapping lives in the registry table at the bottom.
  Adding a new cross-platform tag is one line:
    registry["Icon"] = function(ns, attrs, children) ... end
--]]

local etlua = require("etlua")
local renderData = nil

local function renderTemplate(src, data, sourceName)
    local parser = etlua.Parser()
    local code, err = parser:compile_to_lua(src)
    if not code then return nil, err end
    local fn
    fn, err = parser:load(code, sourceName and ("@" .. sourceName) or nil)
    if not fn then return nil, err end
    local buffer
    buffer, err = parser:run(fn, data)
    if not buffer then return nil, err end
    return table.concat(buffer)
end

local function decodeXMLText(value)
    if type(value) ~= "string" or value == "" then return value end
    value = value:gsub("&#x([%da-fA-F]+);", function(hex)
        local code = tonumber(hex, 16)
        return code and utf8.char(code) or "&#x" .. hex .. ";"
    end)
    value = value:gsub("&#(%d+);", function(decimal)
        local code = tonumber(decimal, 10)
        return code and utf8.char(code) or "&#" .. decimal .. ";"
    end)
    return (value
        :gsub("&quot;", '"')
        :gsub("&apos;", "'")
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&amp;", "&"))
end

-- ── Minimal XML parser ────────────────────────────────────────────────────

local function parseAttrs(attrStr)
    local attrs = {}
    for key, val in attrStr:gmatch('%s+([%w_:%-]+)%s*=%s*"([^"]*)"') do
        attrs[key] = decodeXMLText(val)
    end
    for key, val in attrStr:gmatch("%s+([%w_:%-]+)%s*=%s*'([^']*)'") do
        attrs[key] = decodeXMLText(val)
    end
    return attrs
end

local function parseXML(src, opts)
    opts = opts or {}
    local trimText = opts.trimText ~= false
    local decodeText = opts.decodeText ~= false

    local nodes = {}
    local stack = { { tag = "__root__", attrs = {}, children = nodes } }

    local pos = 1
    local len = #src

    local function current() return stack[#stack] end

    local function pushText(text, isCdata)
        if not isCdata and decodeText then
            text = decodeXMLText(text)
        end
        if trimText and not isCdata then
            text = text:match("^%s*(.-)%s*$")
        end
        if #text > 0 then
            current().children[#current().children + 1] = { kind = "text", value = text }
        end
    end

    while pos <= len do
        local lt = src:find("<", pos, true)
        if not lt then
            pushText(src:sub(pos))
            break
        end

        if lt > pos then
            pushText(src:sub(pos, lt - 1))
        end

        -- comment
        if src:sub(lt, lt + 3) == "<!--" then
            local ce = src:find("-->", lt + 4, true)
            pos = ce and (ce + 3) or (len + 1)

        -- CDATA block
        elseif src:sub(lt, lt + 8) == "<![CDATA[" then
            local ce = src:find("]]>", lt + 9, true)
            if not ce then error("xml: unclosed CDATA near pos " .. lt) end
            pushText(src:sub(lt + 9, ce - 1), true)
            pos = ce + 3

        -- processing instruction
        elseif src:sub(lt, lt + 1) == "<?" then
            local pe = src:find("?>", lt + 2, true)
            pos = pe and (pe + 2) or (len + 1)

        -- doctype/declaration
        elseif src:sub(lt, lt + 8):upper() == "<!DOCTYPE" then
            local de = src:find(">", lt + 9, true)
            pos = de and (de + 1) or (len + 1)

        -- closing tag
        elseif src:sub(lt + 1, lt + 1) == "/" then
            local gt = src:find(">", lt + 2, true)
            if not gt then error("xml: unclosed closing tag near pos " .. lt) end
            if #stack > 1 then table.remove(stack) end
            pos = gt + 1

        -- self-closing or opening tag
        else
            local gt = src:find(">", lt + 1, true)
            if not gt then error("xml: unclosed tag near pos " .. lt) end
            local inner = src:sub(lt + 1, gt - 1)
            local selfClose = inner:sub(-1) == "/"
            if selfClose then inner = inner:sub(1, -2) end

            local tag, rest = inner:match("^([%w_%-%.]+)(.*)$")
            if not tag then error("xml: bad tag near pos " .. lt) end
            local attrs = parseAttrs(rest or "")

            local node = { kind = "element", tag = tag, attrs = attrs, children = {} }
            current().children[#current().children + 1] = node

            if not selfClose then
                stack[#stack + 1] = node
            end
            pos = gt + 1
        end
    end

    return nodes
end

-- ── XML data decoding (schema-driven) ─────────────────────────────────────

local function splitPath(path)
    local parts = {}
    for seg in tostring(path):gmatch("[^/]+") do
        if seg ~= "" and seg ~= "." then parts[#parts + 1] = seg end
    end
    return parts
end

local function elementChildren(node)
    local out = {}
    for _, child in ipairs(node.children or {}) do
        if child.kind == "element" then out[#out + 1] = child end
    end
    return out
end

local function selectNodes(node, path)
    if not path or path == "" or path == "." then
        return { node }
    end
    local current = { node }
    for _, seg in ipairs(splitPath(path)) do
        local nextNodes = {}
        for _, parent in ipairs(current) do
            for _, child in ipairs(parent.children or {}) do
                if child.kind == "element" and child.tag == seg then
                    nextNodes[#nextNodes + 1] = child
                end
            end
        end
        current = nextNodes
        if #current == 0 then break end
    end
    return current
end

local function collectText(node)
    local parts = {}
    local function walk(n)
        for _, child in ipairs(n.children or {}) do
            if child.kind == "text" then
                parts[#parts + 1] = child.value
            elseif child.kind == "element" then
                walk(child)
            end
        end
    end
    walk(node)
    return table.concat(parts)
end

local function toBoolean(value)
    if type(value) == "boolean" then return value end
    if value == nil then return nil end
    local s = tostring(value):lower()
    if s == "true" or s == "1" or s == "yes" then return true end
    if s == "false" or s == "0" or s == "no" then return false end
    return nil
end

local function coerceType(value, typeName)
    if value == nil or typeName == nil then return value end
    if type(typeName) == "function" then return typeName(value) end

    if typeName == "string" then return tostring(value) end
    if typeName == "number" then return tonumber(value) end
    if typeName == "integer" then
        local n = tonumber(value)
        if not n then return nil end
        local i = math.tointeger and math.tointeger(n) or (n % 1 == 0 and n or nil)
        return i
    end
    if typeName == "boolean" then return toBoolean(value) end
    return value
end

local function normalizeFieldSpec(spec)
    if type(spec) == "string" then
        if spec:sub(1, 1) == "@" then
            return { attr = spec:sub(2) }
        end
        if spec == "#text" then
            return { text = true }
        end
        return { path = spec, text = true }
    end
    return spec
end

local decodeWithSchema

local function decodeScalar(node, spec)
    local target = node
    if spec.path then
        target = selectNodes(node, spec.path)[1]
    end

    local value
    if target then
        if spec.attr then
            value = target.attrs and target.attrs[spec.attr] or nil
        else
            value = collectText(target)
            if spec.trim ~= false and type(value) == "string" then
                value = value:match("^%s*(.-)%s*$")
            end
            if spec.text == false then value = nil end
        end
    end

    value = coerceType(value, spec.type)
    if value == nil and spec.default ~= nil then return spec.default end
    return value
end

decodeWithSchema = function(node, spec)
    spec = normalizeFieldSpec(spec)
    if type(spec) ~= "table" then return spec end

    if spec.array then
        local nodes
        if spec.path then
            nodes = selectNodes(node, spec.path)
        elseif spec.tag then
            nodes = selectNodes(node, spec.tag)
        else
            nodes = elementChildren(node)
        end

        local itemSpec
        if spec.of ~= nil then
            itemSpec = spec.of
        elseif spec.fields ~= nil then
            itemSpec = { fields = spec.fields }
        else
            itemSpec = { text = true, type = spec.type }
        end

        local out = {}
        for _, child in ipairs(nodes) do
            out[#out + 1] = decodeWithSchema(child, itemSpec)
        end
        if #out == 0 and spec.default ~= nil then return spec.default end
        return out
    end

    if spec.fields then
        local target = node
        if spec.path then
            target = selectNodes(node, spec.path)[1]
        end
        if not target then
            if spec.default ~= nil then return spec.default end
            return nil
        end

        local out = {}
        for key, fieldSpec in pairs(spec.fields) do
            out[key] = decodeWithSchema(target, fieldSpec)
        end
        return out
    end

    return decodeScalar(node, spec)
end

-- ── Attribute coercion helpers ────────────────────────────────────────────

local function num(v) return tonumber(v) end
local function bool(v) return v == "true" or v == "1" end

local function coerce(v)
    if v == "true"  then return true  end
    if v == "false" then return false end
    local n = tonumber(v)
    if n then return n end
    return v
end

local function layoutProps(attrs)
    local lp = {
        "padding", "paddingHorizontal", "paddingVertical", "paddingTop", "paddingBottom",
        "spacing", "alignment",
        "fixedWidth", "fixedHeight", "minWidth", "minHeight",
        "maxWidth", "maxHeight",
        "flexGrow", "flexShrink", "flexBasis",
		"fillWidth", "fillHeight", "hidden", "background", "cornerRadius", "clipsToBounds", "ignoresSafeArea", "contentMode",
    }
    local props = {}
    for _, k in ipairs(lp) do
        if attrs[k] then props[k] = coerce(attrs[k]) end
    end
    return props
end

-- ── Node → view compilation ───────────────────────────────────────────────
--
-- refs: table populated during compile; any element with a ref="name" attr
-- has its produced view stored as refs[name]. Callers use refs to attach
-- callbacks after rendering without scanning the view tree.

local function compile(nodes, ns, registry, refs)
    local views = {}
    for _, node in ipairs(nodes) do
        if node.kind == "element" then
            local handler = registry[node.tag]
            if not handler then
                error("xml: unknown tag <" .. node.tag .. ">")
            end
            local children = compile(node.children, ns, registry, refs)
            local view = handler(ns, node.attrs, children)
            if view then
                if node.attrs.ref then refs[node.attrs.ref] = view end
                views[#views + 1] = view
            end
        end
    end
    return views
end

-- ── Declarative Tag Schema ────────────────────────────────────────────────
--
-- Tags are defined as data-driven schema tables:
--   kind:        nil (visual view) | "record" (table data / config)
--   constructor: name of constructor on platform module `ns` (defaults to tag name)
--   flag:        table marker for records (e.g. "__toolbarItem", "__isWindowConfig")
--   children:    "array" (props[1..n] = children) | "content" (props.content = children[1]) | "items" (props.items = children)
--   positional:  ordered attribute names mapped to props[1] (with optional .default)
--   directArg:   "positional" -> passes props[1] directly to ctor instead of props table
--   props:       attribute definitions table:
--                  propName = "type"  (types: "num", "bool", "str")
--                  or propName = { prop = "targetName", type = "...", aliases = {...}, default = ... }
--   collect:     optional child aggregation hook: fn(targetTable, children)
--   transform:   optional hook for platform quirks: fn(props, attrs, children, ns) -> optional view

local TAG_SCHEMA = {
    -- Layout containers
    VStack = {
        constructor = "VStack",
        children    = "array",
    },
    HStack = {
        constructor = "HStack",
        children    = "array",
    },
    ZStack = {
        constructor = "ZStack",
        children    = "array",
    },
    HSplit = {
        constructor = "HSplit",
        children    = "array",
    },
    Spacer = {
        constructor = "Spacer",
    },
    PageControl = {
        constructor = "PageControl",
        props = {
            numberOfPages = "num",
            currentPage = "num",
        },
    },
    Divider = {
        constructor = "Divider",
        props = {
            orientation = "str",
        },
    },
    ScrollView = {
        constructor = "ScrollView",
        children    = "content",
        props = {
            contentWidth  = "num",
            contentHeight = "num",
            horizontal    = "bool",
            vertical      = "bool",
        },
    },

    -- Text & Typography
    Label = {
        constructor = "Text",
        positional  = { "text", "value", default = "" },
		props = {
			size       = "num",
			weight     = "str",
			italic     = "bool",
			alignment  = "str",
			color      = "str",
            lines      = { prop = "lineLimit", type = "num" },
            truncation = "str",
        },
        transform = function(props, a)
            if a.lines and (num(a.lines) or 0) > 1 then
                props.lineBreakMode = 0
            end
        end,
    },
    Title = {
        constructor = "Title",
        positional  = { "text", "value", default = "" },
        directArg   = "positional",
    },
    TextEditor = {
        constructor = "TextEditor",
        props = {
            text            = { aliases = { "value" }, default = "", type = "str" },
            size            = "num",
            weight          = "str",
            editable        = "bool",
            selectable      = "bool",
            wrapMode        = "bool",
            drawsBackground = "bool",
        },
    },

    -- Controls & Input
    TextField = {
        constructor = "TextField",
        props = {
            value       = { aliases = { "text" }, default = "", type = "str" },
            placeholder = { default = "", type = "str" },
            editable    = "bool",
            bezeled     = "bool",
            bordered    = "bool",
            size        = "num",
        },
    },
    Button = {
        constructor = "Button",
        props = {
            title       = { aliases = { "label" }, default = "", type = "str" },
            subtitle    = "str",
            systemImage = "str",
            style       = "str",
            detail      = "str",
            truncation  = "str",
        },
        transform = function(props, attrs)
            if attrs.action and renderData and renderData.actions then
                props.action = renderData.actions[attrs.action]
            end
        end,
    },
    Toggle = {
        constructor = "Toggle",
        positional  = { "label", default = "" },
        props = {
            value = { prop = "is_on", aliases = { "checked" }, type = "bool", default = false },
        },
    },
    Slider = {
        constructor = "Slider",
        props = {
            min                      = "num",
            max                      = "num",
            value                    = "num",
            tickMarks                = "num",
            allowsTickMarkValuesOnly = "bool",
        },
    },
    Stepper = {
        constructor = "Stepper",
        props = {
            min        = "num",
            max        = "num",
            value      = "num",
            increment  = "num",
            wraps      = "bool",
            autorepeat = "bool",
        },
    },
    Option = {
        kind  = "record",
        flag  = "__pickerOption",
        props = {
            title = { aliases = { "label", "value" }, default = "", type = "str" },
        },
    },
    Picker = {
        constructor = "Picker",
        props = {
            value = "num",
        },
        collect = function(props, children)
            props.options = {}
            for _, child in ipairs(children) do
                if type(child) == "table" and child.__pickerOption then
                    props.options[#props.options + 1] = child.title
                end
            end
            if #props.options == 0 then
                error("xml: <Picker> requires at least one <Option> child")
            end
        end,
    },

    -- Imagery
    SystemImage = {
        constructor = "SystemImage",
        positional  = { "name", "symbol", default = "" },
        props = {
            size   = "num",
            weight = "str",
            color  = "str",
            label  = { prop = "accessibilityLabel", type = "str" },
        },
        transform = function(props)
            props.accessibilityLabel = props.accessibilityLabel or props[1]
        end,
    },
    Image = {
        constructor = "Image",
        transform = function(props, a, _, ns)
            if a.system or a.symbol then
                props[1] = a.system or a.symbol
                props.accessibilityLabel = a.label or props[1]
                if a.size   then props.size   = num(a.size)   end
                if a.weight then props.weight = a.weight       end
                if a.color  then props.color  = a.color        end
                return ns.SystemImage(props)
            end
            props[1] = a.src or a.path or ""
            return ns.Image(props)
        end,
    },
    LinearGradient = {
        constructor = "LinearGradient",
        props = {
            topAlpha = "num",
            bottomAlpha = "num",
        },
    },

    -- List & Table structures
    Column = {
        kind  = "record",
        flag  = "__column",
        props = {
            id        = "str",
            title     = { default = "", type = "str" },
            width     = "num",
            minWidth  = "num",
            alignment = "str",
        },
    },
    List = {
        constructor = "List",
        props = {
            header          = { default = true, type = "bool" },
            alternatingRows = { default = true, type = "bool" },
            style           = "str",
            bordered        = "bool",
            gridLines       = "str",
        },
        collect = function(props, children)
            local columns = {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__column then
                    columns[#columns + 1] = c
                end
            end
            if #columns == 0 then
                error("xml: <List> requires at least one <Column> child")
            end
            props.columns = columns
        end,
    },

    -- Window & Toolbar structures
    ToolbarItem = {
        kind  = "record",
        flag  = "__toolbarItem",
        props = {
            id      = { default = "", type = "str" },
            label   = { default = "", type = "str" },
            icon    = { default = "", type = "str" },
            tooltip = { default = "", type = "str" },
            action  = "str",
        },
    },
    Toolbar = {
        kind     = "record",
        flag     = "__toolbar",
        children = "items",
    },
    Window = {
        kind  = "record",
        flag  = "__isWindowConfig",
        props = {
            title                      = "str",
            width                      = "num",
            height                     = "num",
            minWidth                   = "num",
            minHeight                  = "num",
            maxWidth                   = "num",
            maxHeight                  = "num",
            appearance                 = "str",
            tabbingMode                = "str",
            tabbingIdentifier          = "str",
            toolbarLabels              = "bool",
            visible                    = "bool",
            sidebarWidth               = "num",
            toolbarContentDividerAfter = "str",
        },
        collect = function(cfg, children)
            local toolbarItems, contentViews = {}, {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__toolbar then
                    for _, item in ipairs(c.items or {}) do
                        if type(item) == "table" and item.__toolbarItem then
                            toolbarItems[#toolbarItems + 1] = item
                        end
                    end
                elseif type(c) == "userdata" or type(c) == "table" then
                    contentViews[#contentViews + 1] = c
                end
            end

            if #toolbarItems > 0 then cfg.toolbar = toolbarItems end

            if #contentViews == 1 then
                cfg.content = contentViews[1]
            elseif #contentViews > 1 then
                local props = {}
                for _, v in ipairs(contentViews) do props[#props + 1] = v end
                cfg.content = props
            end
        end,
    },

    -- Charts
    Chart = {
        transform = function(_, a)
            local key = a.data or "chart"
            if renderData and renderData[key] then return renderData[key] end
            error("xml: <Chart> requires pre-built chart in render data (key: " .. tostring(key) .. ")")
        end,
    },

    -- Navigation
    TabView = {
        constructor = "TabView",
        props = {
            style    = "str",
            selected = "str",
        },
        collect = function(props, children)
            local tabs = {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__tab then
                    tabs[#tabs + 1] = c
                end
            end
            props.tabs = tabs
        end,
    },
    Tab = {
        kind  = "record",
        flag  = "__tab",
        props = {
            id          = "str",
            title       = { aliases = { "label" }, default = "", type = "str" },
            systemImage = "str",
        },
        collect = function(props, children)
            if #children == 1 then
                props.content = children[1]
            elseif #children > 1 then
                props.content = children
            end
        end,
    },
}

-- Tag aliases
local TAG_ALIASES = {
    Text   = "Label",
    Switch = "Toggle",
}

-- ── Tag registry compiler ─────────────────────────────────────────────────

local function coerceValue(val, valType)
    if valType == "bool" then
        return bool(val)
    elseif valType == "num" then
        return num(val)
    else
        return val
    end
end

local function extractProps(propDefs, attrs)
    local props = {}
    if not propDefs then return props end

    for propKey, def in pairs(propDefs) do
        local val = attrs[propKey]
        local targetName = propKey
        local valType = nil
        local defaultVal = nil

        if type(def) == "string" then
            valType = def
        elseif type(def) == "table" then
            targetName = def.prop or propKey
            valType    = def.type
            defaultVal = def.default

            if val == nil and def.aliases then
                for _, alias in ipairs(def.aliases) do
                    if attrs[alias] ~= nil then
                        val = attrs[alias]
                        break
                    end
                end
            end
        end

        if val ~= nil then
            props[targetName] = coerceValue(val, valType)
        elseif defaultVal ~= nil then
            props[targetName] = defaultVal
        end
    end

    return props
end

local function makeSchemaHandler(tag, def)
    return function(ns, attrs, children)
        if def.kind == "record" then
            local rec = extractProps(def.props, attrs)
            if def.flag then rec[def.flag] = true end
            if def.children == "items" then rec.items = children end
            if def.collect then def.collect(rec, children) end
            return rec
        end

        local ctorName = def.constructor or tag
        local ctor = ns and ns[ctorName]
        if not ctor and not def.transform then
            error("xml: platform does not support constructor ns." .. ctorName .. " for tag <" .. tag .. ">")
        end

        local props = layoutProps(attrs)

        -- Positional attribute (e.g. props[1])
        if def.positional then
            local found = false
            for _, key in ipairs(def.positional) do
                if attrs[key] ~= nil then
                    props[1] = attrs[key]
                    found = true
                    break
                end
            end
            if not found and def.positional.default ~= nil then
                props[1] = def.positional.default
            end
        end

        -- Declared properties
        local extracted = extractProps(def.props, attrs)
        for k, v in pairs(extracted) do
            props[k] = v
        end

        if def.children == "array" then
            for _, c in ipairs(children) do
                props[#props + 1] = c
            end
        elseif def.children == "content" then
            local content = children[1]
            if not content then
                error("xml: <" .. tag .. "> requires one content child")
            end
            props.content = content
        end

        if def.collect then
            def.collect(props, children)
        end

        if def.transform then
            local res = def.transform(props, attrs, children, ns)
            if res ~= nil then return res end
        end

        if def.directArg == "positional" then
            return ctor(props[1])
        end

        return ctor(props)
    end
end

local function makeRegistry()
    local R = {}

    -- Compile schema-defined tags
    for tag, def in pairs(TAG_SCHEMA) do
        R[tag] = makeSchemaHandler(tag, def)
    end

    -- Wire tag aliases
    for alias, target in pairs(TAG_ALIASES) do
        R[alias] = R[target]
    end

    return R
end

-- ── Template inheritance & partials ───────────────────────────────────────
--
-- These helpers are injected into the etlua data context so templates can
-- call them directly:
--
--   <% extends("layouts/AppWindow", { title = "Mail" }) %>
--   <% block("content") %> ... <% end %>
--   <%= yield("content") %>
--   <%= partial("MessageRow", msg) %>

local function resolvePath(base, rel)
    if rel:match("^/") or rel:match("^%a:") then return rel end
    local dir = base:match("^(.-)[^/\\]*$")
    return dir .. rel
end

local function nativeReadFile()
    for _, name in ipairs({ "UIKitNative", "AppKitNative" }) do
        local ok, native = pcall(require, name)
        if ok and type(native) == "table" and type(native._readFile) == "function" then
            return native._readFile
        end
    end
    return nil
end

local function readFile(path)
    local reader = nativeReadFile()
    if reader then
        local body, err = reader(path)
        if err then error(err, 2) end
        return body
    end
    local f = io.open(path, "r")
    if not f then
        local msg = "xml: cannot open " .. path
        io.stderr:write(msg .. "\n")
        error(msg, 2)
    end
    local src = f:read("*a")
    f:close()
    return src
end

local function readTemplate(path)
    return readFile(path)
end

-- Build the template helper functions.
-- `ctx` is the data table passed to etlua.render(); we enrich it in-place.
local function injectTemplateHelpers(ctx, baseDir)
    ctx = ctx or {}

    -- Block storage: { [name] = "rendered content string" }
    -- Stored on ctx so it's accessible after etlua.render returns (for deferred extends).
    ctx.__blocks = ctx.__blocks or {}

    -- block("name", "literal content") — content passed as string
    ctx.block = function(name, content)
        if content ~= nil then
            ctx.__blocks[name] = content
        end
    end

    -- yield("name") — emit the content of a block defined in a child template.
    -- Returns empty string if block not defined (allows optional sections).
    ctx.yield = function(name)
        return ctx.__blocks[name] or ""
    end

    -- extends("path", data) — load a parent template.
    -- Parent rendering is DEFERRED until after the child template runs,
    -- so all block() calls execute before yield() reads their content.
    ctx.extends = function(path, parentData)
        local fullPath = resolvePath(baseDir, path)
        ctx.__extendsInfo = {
            path = fullPath,
            data = parentData or {},
            baseDir = baseDir,
        }
    end

    -- partial("path", data) — include a sub-template inline.
    ctx.partial = function(path, partialData)
        local fullPath = resolvePath(baseDir, path)
        local src = readTemplate(fullPath)
        local partialDir = fullPath:match("^(.-)[^/\\]*$")
        local data = partialData or {}
        -- Inject helpers for nested templates
        if type(data) == "table" then
            injectTemplateHelpers(data, partialDir)
        end
        return renderTemplate(src, data, fullPath)
    end

    return ctx
end

-- ── Public API ────────────────────────────────────────────────────────────

local registry = makeRegistry()
local M = {}

-- Render an XML string with optional etlua data and platform module.
-- Returns view, refs where refs is a table of { [refName] = view } for
-- every element that carried a ref="name" attribute.
function M.render(src, data, ns, sourceName)
    ns = ns or require("ns")

    data = type(data) == "table" and data or {}
    local baseDir = data.__baseDir or ""

    injectTemplateHelpers(data, baseDir)

    local ok, result, templateErr = pcall(renderTemplate, src, data, sourceName)
    if not ok then
        local msg = "xml.render: template error: " .. tostring(result)
        io.stderr:write(msg .. "\n")
        error(msg)
    end
    if result == nil then
        error("xml.render: template error: " .. tostring(templateErr))
    end
    src = result
    -- If extends() was called, render the parent now (after all block() calls)
    if data.__extendsInfo then
        local info = data.__extendsInfo
        local parentSrc = readTemplate(info.path)
        local parentDir = info.path:match("^(.-)[^/\\]*$")
        local merged = {}
        for k, v in pairs(info.data) do merged[k] = v end
        for k, v in pairs(data) do
            if type(v) ~= "function" then merged[k] = v end
        end
        injectTemplateHelpers(merged, parentDir)
        merged.yield = function(name)
            return data.__blocks[name] or ""
        end
        local ok2, parentResult, parentErr = pcall(renderTemplate, parentSrc, merged, info.path)
        if not ok2 then
            local msg = "xml.render: error in extends(\"" .. info.path .. "\"): " .. tostring(parentResult)
            io.stderr:write(msg .. "\n")
            error(msg)
        end
        if parentResult == nil then
            error("xml.render: error in extends(\"" .. info.path .. "\"): " .. tostring(parentErr))
        end
        src = parentResult
    end
    -- strip XML declaration / doctype if present
    src = src:gsub("^%s*<%?xml[^?]*%?>%s*", "")
             :gsub("^%s*<!DOCTYPE[^>]*>%s*", "")

    local refs  = {}
    renderData = data
    local nodes = parseXML(src)
    local views = compile(nodes, ns, registry, refs)
    renderData = nil

    -- Window root: return (configTable, refs) — caller passes config to ns.Window
    if #views == 1 and type(views[1]) == "table" and views[1].__isWindowConfig then
        local cfg = views[1]
        cfg.__isWindowConfig = nil
        return cfg, refs
    end

    local root
    if #views == 1 then
        root = views[1]
    else
        -- multiple root nodes: wrap in VStack
        local props = {}
        for _, v in ipairs(views) do props[#props + 1] = v end
        root = ns.VStack(props)
    end
    return root, refs
end

-- Render an XML file.  Path is relative to the process working directory.
function M.renderFile(path, data, ns)
    local src = readFile(path)
    data = type(data) == "table" and data or {}
    data.__baseDir = path:match("^(.-)[^/\\]*$")
    local ok, result, refs = pcall(M.render, src, data, ns, path)
    if not ok then
        local msg = "xml.renderFile [" .. path .. "]: " .. tostring(result)
        io.stderr:write(msg .. "\n")
        error(msg)
    end
    return result, refs
end

-- Decode XML into Lua tables using a schema.
--
-- Schema primitives:
--   { attr = "id", type = "number" }
--   { path = "body", text = true, type = "string" }
--   { path = "messages/message", array = true, fields = { ... } }
--   { fields = { ... } }
-- Shorthands:
--   "@id"    => { attr = "id" }
--   "#text"  => { text = true }
--   "a/b"    => { path = "a/b", text = true }
function M.decode(src, schema)
    schema = schema or {}

    src = src:gsub("^%s*<%?xml[^?]*%?>%s*", "")
             :gsub("^%s*<!DOCTYPE[^>]*>%s*", "")

    local nodes = parseXML(src, { trimText = true, decodeText = true })
    local docRoot = { kind = "element", tag = "__document__", attrs = {}, children = nodes }

    local target = docRoot
    if schema.root then
        target = selectNodes(docRoot, schema.root)[1]
        if not target then
            error("xml.decode: root path not found: " .. tostring(schema.root))
        end
    end

    return decodeWithSchema(target, schema)
end

function M.decodeFile(path, schema)
    local f = assert(io.open(path, "r"), "xml.decodeFile: cannot open " .. path)
    local src = f:read("*a")
    f:close()
    return M.decode(src, schema)
end

-- Expose registry and schema so callers or platform backends can inspect/extend:
--   xml.registry["MyWidget"] = function(ns, attrs, children) ... end
--   xml.schema["MyWidget"] = { ... }
M.registry = registry
M.schema   = TAG_SCHEMA
M.aliases  = TAG_ALIASES

return M
