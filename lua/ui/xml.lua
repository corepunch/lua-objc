--[[
  ui/xml.lua — cross-platform XML template renderer.

  Usage:
    local xml = require("ui.xml")
    local view = xml.render(xmlString, data, ns)

  The `ns` argument is the platform module (AppKit or UIKit). When omitted,
  require("AppKit") is used.  This lets the same XML file produce NSText on
  macOS or UILabel on iOS without any conditionals in the template.

  Workflow for file-based templates:
    local view = xml.renderFile("examples/mail/views/MailRow.xml", rowData, ns)

  etlua is applied to the XML source before parsing, so you can embed data
  with <%= expr %> or execute logic with <% if cond then %> ... <% end %>.

  Tag-to-component mapping lives in the registry table at the bottom.
  Adding a new cross-platform tag is one line:
    registry["Icon"] = function(ns, attrs, children) ... end
--]]

local etlua = require("etlua")

-- ── Minimal XML parser ────────────────────────────────────────────────────

local function parseAttrs(attrStr)
    local attrs = {}
    for key, val in attrStr:gmatch('%s+([%w_:%-]+)%s*=%s*"([^"]*)"') do
        attrs[key] = val
    end
    for key, val in attrStr:gmatch("%s+([%w_:%-]+)%s*=%s*'([^']*)'") do
        attrs[key] = val
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

local function compile(nodes, ns, registry)
    local views = {}
    for _, node in ipairs(nodes) do
        if node.kind == "element" then
            local handler = registry[node.tag]
            if not handler then
                error("xml: unknown tag <" .. node.tag .. ">")
            end
            local children = compile(node.children, ns, registry)
            local view = handler(ns, node.attrs, children)
            if view then views[#views + 1] = view end
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

    return R
end

-- ── Public API ────────────────────────────────────────────────────────────

local registry = makeRegistry()
local M = {}

-- Render an XML string with optional etlua data and platform module.
function M.render(src, data, ns)
    ns = ns or require("AppKit")
    if data then
        local ok, result = pcall(etlua.render, src, data)
        if not ok then error("xml.render: template error: " .. tostring(result)) end
        src = result
    end
    -- strip XML declaration / doctype if present
    src = src:gsub("^%s*<%?xml[^?]*%?>%s*", "")
             :gsub("^%s*<!DOCTYPE[^>]*>%s*", "")

    local nodes = parseXML(src)
    local views = compile(nodes, ns, registry)
    if #views == 1 then return views[1] end
    -- multiple root nodes: wrap in VStack
    local props = {}
    for _, v in ipairs(views) do props[#props + 1] = v end
    return ns.VStack(props)
end

-- Render an XML file.  Path is relative to the process working directory.
function M.renderFile(path, data, ns)
    local f = assert(io.open(path, "r"), "xml.renderFile: cannot open " .. path)
    local src = f:read("*a")
    f:close()
    return M.render(src, data, ns)
end

-- Expose the registry so callers can add custom tags:
--   xml.registry["MyWidget"] = function(ns, attrs, children) ... end
M.registry = registry

return M
