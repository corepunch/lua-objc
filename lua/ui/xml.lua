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

local function parseXML(src)
    local nodes = {}
    local stack = { { tag = "__root__", attrs = {}, children = nodes } }

    local pos = 1
    local len = #src

    local function current() return stack[#stack] end

    local function pushText(text)
        text = text:match("^%s*(.-)%s*$")
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
        "padding", "paddingHorizontal", "paddingVertical",
        "spacing", "alignment",
        "fixedWidth", "fixedHeight", "minWidth", "minHeight",
        "maxWidth", "maxHeight",
        "flexGrow", "flexShrink", "flexBasis",
        "fillWidth", "fillHeight", "hidden",
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

-- ── Tag registry ─────────────────────────────────────────────────────────
--
-- Each entry: function(ns, attrs, children) → view
--
-- `ns` is the platform module passed by the caller, so `ns.Text` is
-- NSTextField on AppKit and UILabel on UIKit — callers never see the diff.

local function makeRegistry()
    local R = {}

    -- Layout containers
    R["VStack"] = function(ns, a, ch)
        local props = layoutProps(a)
        for _, c in ipairs(ch) do props[#props + 1] = c end
        return ns.VStack(props)
    end

    R["HStack"] = function(ns, a, ch)
        local props = layoutProps(a)
        for _, c in ipairs(ch) do props[#props + 1] = c end
        return ns.HStack(props)
    end

    R["HSplit"] = function(ns, a, ch)
        local props = layoutProps(a)
        for _, c in ipairs(ch) do props[#props + 1] = c end
        return ns.HSplit(props)
    end

    R["Spacer"] = function(ns, a, _)
        return ns.Spacer(layoutProps(a))
    end

    R["Divider"] = function(ns, a, _)
        local props = layoutProps(a)
        if a.orientation then props.orientation = a.orientation end
        return ns.Divider(props)
    end

    -- Text / labels
    -- <Label text="Hello" size="13" weight="bold" color="secondary" />
    -- Maps to ns.Text on both platforms (UIKit aliases Text=Label).
    R["Label"] = function(ns, a, ch)
        local props = layoutProps(a)
        props[1] = a.text or a.value or ""
        if a.size   then props.size   = num(a.size)   end
        if a.weight then props.weight = a.weight       end
        if a.color  then props.color  = a.color        end
        if a.lines  then props.lineLimit = num(a.lines) end
        if a.truncation then props.truncation = a.truncation end
        return ns.Text(props)
    end

    R["Text"] = R["Label"]

    R["TextEditor"] = function(ns, a, _)
        local props = layoutProps(a)
        props.text = a.text or a.value or ""
        if a.size then props.size = num(a.size) end
        if a.weight then props.weight = a.weight end
        if a.editable ~= nil then props.editable = bool(a.editable) end
        if a.selectable ~= nil then props.selectable = bool(a.selectable) end
        if a.wrapMode ~= nil then props.wrapMode = bool(a.wrapMode) end
        if a.drawsBackground ~= nil then props.drawsBackground = bool(a.drawsBackground) end
        return ns.TextEditor(props)
    end

    R["Title"] = function(ns, a, _)
        return ns.Title(a.text or a.value or "")
    end

    -- Input
    R["TextField"] = function(ns, a, _)
        local props = layoutProps(a)
        props.value       = a.value or a.text or ""
        props.placeholder = a.placeholder or ""
        if a.editable  ~= nil then props.editable  = bool(a.editable)  end
        if a.bezeled   ~= nil then props.bezeled   = bool(a.bezeled)   end
        if a.bordered  ~= nil then props.bordered  = bool(a.bordered)  end
        if a.size      ~= nil then props.size      = num(a.size)       end
        return ns.TextField(props)
    end

    -- Button
    R["Button"] = function(ns, a, _)
        local props = layoutProps(a)
        props.title = a.title or a.label or ""
        if a.subtitle    then props.subtitle    = a.subtitle    end
        if a.systemImage then props.systemImage = a.systemImage end
        if a.style       then props.style       = a.style       end
        if a.detail      then props.detail      = a.detail      end
        return ns.Button(props)
    end

    -- Image
    R["Image"] = function(ns, a, _)
        if a.system or a.symbol then
            local props = layoutProps(a)
            props[1]                = a.system or a.symbol
            props.accessibilityLabel = a.label or props[1]
            if a.size   then props.size   = num(a.size)   end
            if a.weight then props.weight = a.weight       end
            if a.color  then props.color  = a.color        end
            return ns.SystemImage(props)
        end
        local props = layoutProps(a)
        props[1] = a.src or a.path or ""
        return ns.Image(props)
    end

    R["SystemImage"] = function(ns, a, _)
        local props = layoutProps(a)
        props[1]                = a.name or a.symbol or ""
        props.accessibilityLabel = a.label or props[1]
        if a.size   then props.size   = num(a.size)   end
        if a.weight then props.weight = a.weight       end
        if a.color  then props.color  = a.color        end
        return ns.SystemImage(props)
    end

    -- Toggle / Switch
    R["Toggle"] = function(ns, a, _)
        local props = layoutProps(a)
        props[1]   = a.label or ""
        props.is_on = bool(a.value or a.checked or "false")
        return ns.Toggle(props)
    end
    R["Switch"] = R["Toggle"]

    -- List / Column
    -- <List ref="msgList" style="plain" header="false" alternatingRows="false">
    --   <Column id="from" title="From" />
    --   <Column id="subject" title="Subject" />
    -- </List>
    -- Column children are collected here; data is supplied at runtime via list:replaceRows().
    R["Column"] = function(_, a, _)
        -- Returns a plain table, not a view — List consumes it before returning.
        return { __column = true, id = a.id, title = a.title or "",
                 width = num(a.width), minWidth = num(a.minWidth),
                 alignment = a.alignment }
    end

    R["List"] = function(ns, a, children)
        local columns, views = {}, {}
        for _, c in ipairs(children) do
            if type(c) == "table" and c.__column then
                columns[#columns + 1] = c
            else
                views[#views + 1] = c
            end
        end
        if #columns == 0 then
            error("xml: <List> requires at least one <Column> child")
        end
        local props = layoutProps(a)
        props.columns          = columns
        props.header           = a.header  ~= nil and bool(a.header)  or true
        props.alternatingRows  = a.alternatingRows ~= nil and bool(a.alternatingRows) or true
        props.style            = a.style
        if a.bordered  ~= nil then props.bordered  = bool(a.bordered)  end
        if a.gridLines         then props.gridLines = a.gridLines       end
        -- views inside List (unusual) are ignored; columns are all we need
        return ns.List(props)
    end

    -- Window / Toolbar (NIB-style declarative window config)
    -- <ToolbarItem> returns a plain table, consumed by <Window>.
    R["ToolbarItem"] = function(_, a, _)
        return {
            __toolbarItem = true,
            id      = a.id or "",
            label   = a.label or "",
            icon    = a.icon or "",
            tooltip = a.tooltip or "",
            action  = a.action or nil,
        }
    end

    -- <Toolbar> is a passthrough; its ToolbarItem children are collected by <Window>.
    R["Toolbar"] = function(_, _, children)
        return { __toolbar = true, items = children }
    end

    -- <Window> captures window config and wraps content.
    -- Returns a config table (not a view) — detected by render().
    R["Window"] = function(_, a, children)
        local cfg = {}

        -- Window properties
        if a.title          then cfg.title          = a.title          end
        if a.width          then cfg.width          = num(a.width)     end
        if a.height         then cfg.height         = num(a.height)    end
        if a.minWidth       then cfg.minWidth       = num(a.minWidth)  end
        if a.minHeight      then cfg.minHeight      = num(a.minHeight) end
        if a.maxWidth       then cfg.maxWidth       = num(a.maxWidth)  end
        if a.maxHeight      then cfg.maxHeight      = num(a.maxHeight) end
        if a.appearance     then cfg.appearance     = a.appearance     end
        if a.tabbingMode    then cfg.tabbingMode    = a.tabbingMode    end
        if a.tabbingIdentifier then cfg.tabbingIdentifier = a.tabbingIdentifier end
        if a.toolbarLabels  then cfg.toolbarLabels  = bool(a.toolbarLabels) end
        if a.visible        then cfg.visible        = bool(a.visible)  end
        if a.sidebarWidth   then cfg.sidebarWidth   = num(a.sidebarWidth) end
        if a.toolbarContentDividerAfter then
            cfg.toolbarContentDividerAfter = a.toolbarContentDividerAfter
        end

        -- Separate toolbar items from content children
        local toolbarItems = {}
        local contentViews = {}
        for _, c in ipairs(children) do
            if type(c) == "table" then
                if c.__toolbar then
                    for _, item in ipairs(c.items) do
                        if type(item) == "table" and item.__toolbarItem then
                            toolbarItems[#toolbarItems + 1] = item
                        end
                    end
                else
                    contentViews[#contentViews + 1] = c
                end
            elseif type(c) == "userdata" then
                -- Views (userdata) are direct content
                contentViews[#contentViews + 1] = c
            end
        end

        if #toolbarItems > 0 then cfg.toolbar = toolbarItems end

        -- Wrap content: single child passthrough, multiple → VStack
        if #contentViews == 1 then
            cfg.content = contentViews[1]
        elseif #contentViews > 1 then
            local props = {}
            for _, v in ipairs(contentViews) do props[#props + 1] = v end
            cfg.content = props  -- VStack will be created by ns.Window
        end

        -- Mark as window config so render() can detect it
        cfg.__isWindowConfig = true
        return cfg
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

local function readTemplate(path)
    local f = assert(io.open(path, "r"), "xml: cannot open " .. path)
    local src = f:read("*a")
    f:close()
    return src
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
        return etlua.render(src, data)
    end

    return ctx
end

-- ── Public API ────────────────────────────────────────────────────────────

local registry = makeRegistry()
local M = {}

-- Render an XML string with optional etlua data and platform module.
-- Returns view, refs where refs is a table of { [refName] = view } for
-- every element that carried a ref="name" attribute.
function M.render(src, data, ns)
    ns = ns or require("AppKit")

    data = type(data) == "table" and data or {}
    local baseDir = data.__baseDir or ""

    injectTemplateHelpers(data, baseDir)

    local ok, result = pcall(etlua.render, src, data)
    if not ok then error("xml.render: template error: " .. tostring(result)) end
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
        -- Yield reads from the blocks collected during child processing
        merged.yield = function(name)
            return data.__blocks[name] or ""
        end
            local ok2, parentResult = pcall(etlua.render, parentSrc, merged)
            if not ok2 then error("xml.render: template error in parent: " .. tostring(parentResult)) end
            src = parentResult
    end
    -- strip XML declaration / doctype if present
    src = src:gsub("^%s*<%?xml[^?]*%?>%s*", "")
             :gsub("^%s*<!DOCTYPE[^>]*>%s*", "")

    local refs  = {}
    local nodes = parseXML(src)
    local views = compile(nodes, ns, registry, refs)

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
    local f = assert(io.open(path, "r"), "xml.renderFile: cannot open " .. path)
    local src = f:read("*a")
    f:close()
    -- Pass base directory so extends/partial can resolve relative paths
    data = type(data) == "table" and data or {}
    data.__baseDir = path:match("^(.-)[^/\\]*$")
    return M.render(src, data, ns)
end

-- Expose the registry so callers can add custom tags:
--   xml.registry["MyWidget"] = function(ns, attrs, children) ... end
M.registry = registry

return M
