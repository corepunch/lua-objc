--[[
  ui/xml.lua — cross-platform XML template renderer.

  Usage:
    local xml = require("ui.xml")
    local view = xml.render(xmlString, data, ns)

  The `ns` argument is the platform module (AppKit or UIKit). When omitted,
  require("AppKit") is used.  This lets the same XML file produce NSText on
  macOS or UILabel on iOS without any conditionals in the template.

  Workflow for file-based templates:
    local view = xml.renderFile("demo/mail/views/MailRow.etlua", rowData, ns)

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
            table.insert(current().children, { kind = "text", value = text })
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
            table.insert(current().children, node)

            if not selfClose then
                table.insert(stack, node)
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
        if seg ~= "" and seg ~= "." then table.insert(parts, seg) end
    end
    return parts
end

local function elementChildren(node)
    local out = {}
    for _, child in ipairs(node.children or {}) do
        if child.kind == "element" then table.insert(out, child) end
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
                    table.insert(nextNodes, child)
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
                table.insert(parts, child.value)
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
            table.insert(out, (decodeWithSchema(child, itemSpec)))
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
        "padding", "paddingHorizontal", "paddingVertical", "paddingLeading", "paddingTrailing", "paddingTop", "paddingBottom",
        "spacing", "alignment", "maxRows",
        "flexGrow", "flexShrink", "flexBasis",
        "hidden", "allowsHitTesting", "background", "cornerRadius", "clipsToBounds", "ignoresSafeArea", "contentMode", "onClick", "onTap", "onDrag", "onEdgeSwipe",
    }
    local props = {}
    for _, k in ipairs(lp) do
        if attrs[k] then props[k] = coerce(attrs[k]) end
    end
	-- Templates use SwiftUI dimension names; fixed/fill flags belong to the
	-- native layout engine. Infinity is a proposal, never a native frame size.
	for _, axis in ipairs({ "Width", "Height" }) do
		local dimension = axis:lower()
		if attrs[dimension] then
			local value = tonumber(attrs[dimension])
			if not value or value < 0 or value ~= value or value == math.huge then
				error("xml: " .. dimension .. " requires a nonnegative finite number")
			end
			props["fixed" .. axis] = value
		end
		local maximum = "max" .. axis
		local minimum = "min" .. axis
		for _, key in ipairs({ minimum, maximum }) do
			if attrs[key] == "infinity" and key == maximum then
				props["fill" .. axis] = true
			elseif attrs[key] then
				local value = tonumber(attrs[key])
				if not value or value < 0 or value ~= value or value == math.huge then
					error("xml: " .. key .. " requires a nonnegative finite number"
						.. (key == maximum and " or infinity" or ""))
				end
				props[key] = value
			end
		end
		if props[minimum] and props[maximum] and props[minimum] > props[maximum] then
			error("xml: " .. minimum .. " exceeds " .. maximum)
		end
	end
    if attrs.onClick and type(attrs.onClick) == "string"
        and renderData and renderData.actions then

        props.onClick = renderData.actions[attrs.onClick]
    end
    for _, key in ipairs({ "onTap", "onDrag", "onEdgeSwipe" }) do
        if attrs[key] and type(attrs[key]) == "string" and renderData and renderData.actions then
            props[key] = renderData.actions[attrs[key]]
        end
    end
    return props
end

-- ── Node → view compilation ───────────────────────────────────────────────
--
-- refs: table populated during compile; any view with an id="name" attr
-- has its produced view stored as refs[name]. Callers use refs to attach
-- callbacks after rendering without scanning the view tree.

local function compile(nodes, ns, registry, refs)
    local views = {}
    for _, node in ipairs(nodes) do
        if node.kind == "element" then
			for _, key in ipairs({ "fillWidth", "fillHeight", "fixedWidth", "fixedHeight" }) do
				if node.attrs[key] ~= nil then
					error("xml: " .. key .. " was removed; use width/height or maxWidth/maxHeight=\"infinity\"")
				end
			end
            local handler = registry[node.tag]
            if not handler then
                error("xml: unknown tag <" .. node.tag .. ">")
            end
			local lazy = node.tag == "LazyVStack" or node.tag == "LazyVGrid"
			local children
			if lazy then
				local itemNodes = {}
				for _, child in ipairs(node.children) do
					if child.kind == "element" then itemNodes[#itemNodes + 1] = child end
				end
				local itemData = renderData
				children = {
					count = #itemNodes,
					factory = function(index)
						local previous = renderData
						renderData = itemData
						local ok, item = pcall(function()
							return compile({ itemNodes[index] }, ns, registry, {})[1]
						end)
							renderData = previous
							if not ok then error(item) end
							if type(item) ~= "userdata" then
								error("xml: lazy collection items must render one native view")
							end
							return item
					end,
				}
			else
				children = compile(node.children, ns, registry, refs)
			end
			local view = handler(ns, node.attrs, children)
			if view then
				if node.attrs.reorderable == "true" and node.tag ~= "List" and not lazy then
					local name = node.attrs.reorderContainer
					local action = name and renderData and renderData.actions
						and renderData.actions[name]
					if type(action) ~= "function" then
						error("xml: reorderable <" .. node.tag ..
							"> requires a valid reorderContainer action")
					end
					local items = {}
					local function append(childrenToAdd)
						for _, child in ipairs(childrenToAdd) do
							if type(child) == "table" and child.__appkitGroup then
								append(child)
							else
								items[#items + 1] = child
							end
						end
					end
					append(children)
					view = ns.attachReorder(view, items, action)
				end
				if node.attrs.id and type(view) == "userdata" then
					refs[node.attrs.id] = view
					-- Keep the declarative identity on the native view as well as
					-- in the returned refs table. Diagnostics and accessibility
					-- tooling can then locate the same semantic node without
					-- depending on child order or implementation classes.
					pcall(function()
						view.accessibilityIdentifier = node.attrs.id
					end)
				end
				table.insert(views, view)
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
        props = {
        },
    },
    LazyVStack = {
        constructor = "LazyVStack",
        props = { rowHeight = "num", reorderable = "bool", reorderContainer = "str" },
        collect = function(props, children)
            props.itemCount, props.itemFactory = children.count, children.factory
        end,
        transform = function(props, attrs)
            if attrs.reorderable == "true" then
                props.onReorder = attrs.reorderContainer and renderData
                    and renderData.actions and renderData.actions[attrs.reorderContainer]
                if type(props.onReorder) ~= "function" then
                    error("xml: reorderable <LazyVStack> requires a valid reorderContainer action")
                end
            end
        end,
    },
    LazyVGrid = {
        constructor = "LazyVGrid",
        props = { columns = "num", rowHeight = "num", reorderable = "bool",
            reorderContainer = "str" },
        collect = function(props, children)
            props.itemCount, props.itemFactory = children.count, children.factory
        end,
        transform = function(props, attrs)
            if attrs.reorderable == "true" then
                props.onReorder = attrs.reorderContainer and renderData
                    and renderData.actions and renderData.actions[attrs.reorderContainer]
                if type(props.onReorder) ~= "function" then
                    error("xml: reorderable <LazyVGrid> requires a valid reorderContainer action")
                end
            end
        end,
    },
    FlowStack = {
        constructor = "FlowStack",
        children = "array",
    },
    HStack = {
        constructor = "HStack",
        children    = "array",
        props = {
        },
    },
    Section = {
        constructor = "Section",
        children    = "array",
        props = { header = "str" },
    },
    GroupBox = {
        constructor = "GroupBox",
        children    = "array",
        props = { header = "str" },
    },
    Form = {
        constructor = "Form",
        children    = "array",
        props = { spacing = "num", alignment = "str" },
    },
    LabeledContent = {
        constructor = "LabeledContent",
        children    = "array",
        props = { label = "str", labelWeight = "str", spacing = "num" },
    },
    ControlGroup = {
        constructor = "ControlGroup",
        children    = "array",
        props = { spacing = "num", alignment = "str" },
    },
    DisclosureGroup = {
        constructor = "DisclosureGroup",
        children    = "array",
        props = {
            label = "str",
            header = "str",
            expanded = "bool",
        },
    },
    Grid = {
        constructor = "Grid",
        children    = "array",
    },
    GridRow = {
        constructor = "Group",
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
    ProgressView = {
        constructor = "ProgressView",
        props = {
            value = "num",
            indeterminate = "bool",
            tint = "str",
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
    SafeAreaInset = {
        constructor = "SafeAreaInset",
        children = "array",
        props = { edge = "str" },
    },

    -- Text & Typography
    Label = {
        constructor = "Text",
        positional  = { "text", "value", default = "" },
		props = {
            size       = "num",
            weight     = "str",
			design     = "str",
            italic     = "bool",
			systemImage = "str",
			iconSize   = "num",
			iconWeight = "str",
			spacing    = "num",
			alignment  = "str",
			color      = "str",
			accessibilityLabel = "str",
            lines      = { prop = "lineLimit", type = "num" },
            truncation = "str",
            wrapping = "str",
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
    Preview = { constructor = "Preview" },
    TextEditor = {
        constructor = "TextEditor",
        props = {
            text            = { aliases = { "value" }, default = "", type = "str" },
            size            = "num",
            weight          = "str",
			design          = "str",
            editable        = "bool",
            selectable      = "bool",
            wrapMode        = "bool",
            drawsBackground = "bool",
        },
    },
    SearchField = {
        constructor = "SearchField",
        props = {
            value = { aliases = { "text" }, default = "", type = "str" },
            placeholder = { default = "Search", type = "str" },
            accessibilityLabel = "str",
        },
        transform = function(props, attrs)
            if attrs.onChange and renderData and renderData.actions then
                props.onChange = renderData.actions[attrs.onChange]
            end
        end,
    },

    -- Controls & Input
    TextField = {
        constructor = "TextField",
        props = {
            value       = { aliases = { "text" }, default = "", type = "str" },
            placeholder = { default = "", type = "str" },
			style       = "str",
					editable    = "bool",
					secure     = "bool",
            bezeled     = "bool",
            bordered    = "bool",
            size        = "num",
			design      = "str",
			disabled    = "bool",
        },
        transform = function(props, attrs)
            if renderData and renderData.actions then
                if attrs.onChange then props.onChange = renderData.actions[attrs.onChange] end
                if attrs.onCommand then props.onCommand = renderData.actions[attrs.onCommand] end
            end
        end,
    },
    Button = {
        constructor = "Button",
        collect = function(props, children)
			if #children > 1 then error("xml: Button accepts one label view; group siblings in a stack") end
			props.content = children[1]
			if props.content and props.style ~= "plain" then
				error("xml: a Button with a label view requires style=\"plain\"")
			end
		end,
        props = {
            accessibilityLabel = "str",
            size        = "num",
            weight      = "str",
            title       = { aliases = { "label" }, default = "", type = "str" },
            subtitle    = "str",
            systemImage = "str",
			symbolSize = "num",
            foregroundStyle = "str",
            style       = "str",
            cornerRadius = "num",
            role        = "str",
            detail      = "str",
            truncation  = "str",
            disabled    = "bool",
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
			disabled = "bool",
        },
    },
    Link = {
        constructor = "Link",
        props = {
            title = { aliases = { "label" }, default = "", type = "str" },
            url = { default = "", type = "str" },
        },
    },
    Menu = {
        constructor = "Menu",
        children = "items",
        props = {
			title = "str",
			systemImage = "str",
			style = "str",
			symbolSize = "num",
			accessibilityLabel = "str",
		},
        collect = function(props, children)
            props.items = children
        end,
    },
    MenuItem = {
        kind = "record",
        flag = "__menuItem",
        props = {
            title = { aliases = { "label" }, default = "", type = "str" },
            systemImage = "str",
            role = "str",
        },
		transform = function(props, attrs)
			if attrs.action and renderData and renderData.actions then
				props.action = renderData.actions[attrs.action]
			end
		end,
    },
    ContentUnavailable = {
        constructor = "ContentUnavailable",
        props = {
            title = "str",
            systemImage = "str",
            description = "str",
            imageSize = "num",
            lines = "num",
        },
    },
    MaterialView = {
        constructor = "MaterialView",
        children = "content",
        props = { material = "str" },
    },
    GlassEffect = {
        constructor = "GlassEffect",
        children = "content",
		props = { style = "str", cornerRadius = "num", interactive = "bool", accessibilityLabel = "str" },
    },
    GlassEffectContainer = {
		constructor = "GlassEffectContainer",
		children = "content",
		props = { spacing = "num" },
	},
    Slider = {
        constructor = "Slider",
        props = {
            min                      = "num",
            max                      = "num",
            value                    = "num",
            tickMarks                = "num",
            allowsTickMarkValuesOnly = "bool",
			disabled                = "bool",
        },
		transform = function(props, attrs)
			if attrs.onChange and renderData and renderData.actions then
				props.onChange = renderData.actions[attrs.onChange]
			end
		end,
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
			disabled   = "bool",
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
			style = "str",
			disabled = "bool",
        },
        collect = function(props, children)
            props.options = {}
            for _, child in ipairs(children) do
                if type(child) == "table" and child.__pickerOption then
                    table.insert(props.options, child.title)
                end
            end
            if #props.options == 0 then
                error("xml: <Picker> requires at least one <Option> child")
            end
        end,
		transform = function(props, attrs)
			if attrs.onChange and renderData and renderData.actions then
				props.action = renderData.actions[attrs.onChange]
			end
		end,
    },
    DatePicker = {
        constructor = "DatePicker",
        props = {
            timestamp = { aliases = { "time" }, type = "num" },
            disabled = "bool",
        },
    },
    ColorPicker = {
        constructor = "ColorPicker",
        props = { color = "str", disabled = "bool" },
    },

    -- Imagery
    SystemImage = {
        constructor = "SystemImage",
        positional  = { "name", "symbol", default = "" },
        props = {
            size   = "num",
            weight = "str",
            color  = "str",
            badgeColor = "str",
            appIcon = "str",
            label  = { prop = "accessibilityLabel", type = "str" },
        },
        transform = function(props)
            props.accessibilityLabel = props.accessibilityLabel or props[1]
        end,
    },
    Image = {
        constructor = "Image",
        props = { resizable = "bool" },
        transform = function(props, a, _, ns)
            if a.system or a.symbol then
                props[1] = a.system or a.symbol
                props.accessibilityLabel = a.label or props[1]
                if a.size   then props.size   = num(a.size)   end
                if a.weight then props.weight = a.weight       end
                if a.color  then props.color  = a.color        end
                return ns.SystemImage(props)
            end
            props.fileIcon = bool(a.fileIcon)
            props[1] = a.src or a.path or ""
            return ns.Image(props)
        end,
    },
    LinearGradient = {
        constructor = "LinearGradient",
        props = {
            topAlpha = "num",
            middleAlpha = "num",
            middleLocation = "num",
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
            sortable  = "bool",
            width     = "num",
            minWidth  = "num",
            alignment = "str",
            systemImage = "str",
            imageKey = "str",
            subtitleKey = "str",
            fileIconKey = "str",
            imageColorKey = "str",
            badgeColorKey = "str",
            appIconKey = "str",
            imageSize = "num",
            levelKey = "str",
            levelColorKey = "str",
            loadingKey = "str",
            controlSize = "str",
        },
        collect = function(props)
            for key, field in pairs({loadingKey = "loading", controlSize = "controlSize", badgeColorKey = "badgeColor", appIconKey = "appIcon", subtitleKey = "secondary", fileIconKey = "fileIcon", imageKey = "image", imageColorKey = "imageColor", imageSize = "imageSize", levelKey = "level", levelColorKey = "levelColor"}) do
                if props[key] then
                    props.cell = props.cell or {}
                    props.cell[field] = props[key]
                    props[key] = nil
                end
            end
        end,
    },
    List = {
        constructor = "List",
        props = {
            data = "str",
            header          = { default = true, type = "bool" },
            alternatingRows = { default = true, type = "bool" },
            drawsBackground = "bool",
            rowHeight = "num",
            style           = "str",
            bordered        = "bool",
            gridLines       = "str",
            reorderable = "bool",
            reorderContainer = "str",
            swipeLeading = "str",
            swipeTrailing = "str",
            swipeLeadingTitle = "str",
            swipeTrailingTitle = "str",
            swipeLeadingRole = "str",
            swipeTrailingRole = "str",
            fullSwipe = "bool",
        },
        collect = function(props, children)
            local columns = {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__column then
                    table.insert(columns, c)
                end
            end
            if #columns == 0 then
                error("xml: <List> requires at least one <Column> child")
            end
            props.columns = columns
        end,
        transform = function(props, attrs)
            if attrs.data and renderData then
                props.data = renderData[attrs.data]
            end
            if attrs.reorderContainer then
                props.onReorder = renderData and renderData.actions
                    and renderData.actions[attrs.reorderContainer]
            end
            if props.reorderable and type(props.onReorder) ~= "function" then
                error("xml: reorderable <List> requires a valid reorderContainer action")
            end
            if attrs.swipeLeading then
                props.onSwipeLeading = renderData and renderData.actions
                    and renderData.actions[attrs.swipeLeading]
                if type(props.onSwipeLeading) ~= "function" then
                    error("xml: swipeLeading requires a valid controller action")
                end
            end
            if attrs.swipeTrailing then
                props.onSwipeTrailing = renderData and renderData.actions
                    and renderData.actions[attrs.swipeTrailing]
                if type(props.onSwipeTrailing) ~= "function" then
                    error("xml: swipeTrailing requires a valid controller action")
                end
            end
        end,
    },
    SwipeRow = {
        constructor = "SwipeRow",
        props = {
            rowId = "str",
            title = { default = "", type = "str" },
            status = "str",
            rowHeight = "num",
            swipeLeading = "str",
            swipeTrailing = "str",
            swipeLeadingTitle = "str",
            swipeTrailingTitle = "str",
            swipeLeadingRole = "str",
            swipeTrailingRole = "str",
            fullSwipe = "bool",
        },
        transform = function(props, attrs)
            for _, edge in ipairs({ "Leading", "Trailing" }) do
                local name = attrs["swipe" .. edge]
                if name then
                    props["onSwipe" .. edge] = renderData and renderData.actions
                        and renderData.actions[name]
                    if type(props["onSwipe" .. edge]) ~= "function" then
                        error("xml: swipe" .. edge .. " requires a valid controller action")
                    end
                end
            end
        end,
    },
    OutlineView = {
        constructor = "OutlineView",
        props = {
            header          = { default = true, type = "bool" },
            alternatingRows = { default = true, type = "bool" },
            drawsBackground = "bool",
            rowHeight = "num",
            style           = "str",
            bordered        = "bool",
            gridLines       = "str",
        },
        collect = function(props, children)
            local columns = {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__column then
                    table.insert(columns, c)
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
            bordered = "bool",
            visibilityPriority = "num",
        },
        collect = function(rec, children)
            if #children == 1 then
                rec.view = children[1]
            elseif #children > 1 then
                error("xml: <ToolbarItem> accepts at most one view child")
            end
        end,
    },
    Toolbar = {
        kind     = "record",
        flag     = "__toolbar",
        children = "items",
    },
    ToolbarSpacer = {
        kind = "record",
        flag = "__toolbarItem",
        props = {
            id = { default = "flexibleSpace", type = "str" },
        },
    },
    Sheet = {
        constructor = "Sheet",
        children = "array",
        props = { width = "num", height = "num" },
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
            detailWidth                = "num",
            toolbarContentDividerAfter = "str",
        },
        collect = function(cfg, children)
            local toolbarItems, contentViews = {}, {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__toolbar then
                    for _, item in ipairs(c.items or {}) do
                        if type(item) == "table" and item.__toolbarItem then
                            table.insert(toolbarItems, item)
                        end
                    end
                elseif type(c) == "userdata" or type(c) == "table" then
                    table.insert(contentViews, c)
                end
            end

            if #toolbarItems > 0 then cfg.toolbar = toolbarItems end

            if #contentViews == 1 then
                cfg.content = contentViews[1]
            elseif #contentViews > 1 then
                local props = {}
                for _, v in ipairs(contentViews) do table.insert(props, v) end
                cfg.content = props
            end
        end,
        transform = function(cfg)
            if renderData and renderData.actions then
                for _, item in ipairs(cfg.toolbar or {}) do
                    if type(item.action) == "string" then
                        item.action = renderData.actions[item.action]
                    end
                end
            end
        end,
    },

    -- Charts
    WebView = {
        constructor = "WebView",
        props = {
            page = "str",
            url = "str",
            contentBackground = "str",
            allowsBackForwardNavigation = { default = true, type = "bool" },
            pageZoom = "num",
            allowsMagnification = "bool",
        },
        transform = function(props)
            if type(props.page) == "string" and renderData then
                props.page = renderData[props.page]
            end
        end,
    },

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
            style = "str",
            selected = "str",
            minimizeBehavior = "str",
        },
        collect = function(props, children)
            local tabs = {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__tab then
                    table.insert(tabs, c)
                end
            end
            props.tabs = tabs
        end,
    },
    NavigationStack = {
        constructor = "NavigationStack",
        children = "array",
        props = {
            title = "str",
            largeTitle = "bool",
            hidesTabBar = "bool",
            hidesNavigationBar = "bool",
            path = "str",
            destinations = "str",
            enablePrivateNavigationPalettes = "bool",
        },
        collect = function(props, children)
            local content
            for _, child in ipairs(children) do
                if type(child) == "table" and child.__navigationPalette then
                    props[child.edge .. "Palette"] = child.content
                elseif content == nil then
                    content = child
                else
                    error("xml: <NavigationStack> requires one content child")
                end
            end
            if not content then error("xml: <NavigationStack> requires one content child") end
            props.content = content
            for index = #props, 1, -1 do props[index] = nil end
        end,
        transform = function(props)
            if renderData then
                if type(props.path) == "string" then props.path = renderData[props.path] end
                if type(props.destinations) == "string" then
                    props.destinations = renderData[props.destinations]
                end
            end
        end,
    },
    TopPalette = {
        kind = "record", flag = "__navigationPalette",
        collect = function(props, children)
            if #children ~= 1 then error("xml: <TopPalette> requires one view") end
            props.edge, props.content = "top", children[1]
        end,
    },
    BottomPalette = {
        kind = "record", flag = "__navigationPalette",
        collect = function(props, children)
            if #children ~= 1 then error("xml: <BottomPalette> requires one view") end
            props.edge, props.content = "bottom", children[1]
        end,
    },
    NavigationLink = {
        constructor = "NavigationLink",
        children = "content",
        props = {
            value = "str",
            destination = "str",
            title = "str",
        },
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
			if def.transform then def.transform(rec, attrs, children, ns) end
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
                table.insert(props, c)
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

-- Evaluate etlua without creating native views or mutating caller bindings.
function M.describe(src, data, sourceName)
    local context = {}
    for key, value in pairs(type(data) == "table" and data or {}) do context[key] = value end
    data = context
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

    return {source = src, data = data}
end

function M.renderDescription(description, ns)
    ns = ns or require("ns")
    local refs = {}
    local previous = renderData
    renderData = description.data
    local ok, views = pcall(function()
        return compile(parseXML(description.source), ns, registry, refs)
    end)
    renderData = previous
    if not ok then error(views) end

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
        for _, v in ipairs(views) do table.insert(props, v) end
        root = ns.VStack(props)
    end
    return root, refs
end

function M.render(src, data, ns, sourceName)
    return M.renderDescription(M.describe(src, data, sourceName), ns)
end

function M.describeFile(path, data)
    local context = {}
    for key, value in pairs(data or {}) do context[key] = value end
    context.__baseDir = path:match("^(.-)[^/\\]*$")
    return M.describe(readFile(path), context, path)
end

-- Render an XML file.  Path is relative to the process working directory.
function M.renderFile(path, data, ns)
    local ok, result, refs = pcall(function()
        return M.renderDescription(M.describeFile(path, data), ns)
    end)
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
