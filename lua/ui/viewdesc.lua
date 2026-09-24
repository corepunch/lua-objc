--[[
  ui/viewdesc.lua — View description format for diffing and patching.

  Instead of compiling XML directly to live native views, this module
  compiles to a plain table describing the view tree. Two descriptions
  can be diffed, and the diff can be applied to native views.

  This enables efficient updates: only changed views are recreated.

  Usage:
    local viewdesc = require("ui.viewdesc")
    local xml = require("ui.xml")

    -- Generate description from template
    local desc = viewdesc.fromFile("views/Window.etlua", data)

    -- Later, with new data
    local newDesc = viewdesc.fromFile("views/Window.etlua", newData)

    -- Diff
    local patches = viewdesc.diff(desc, newDesc)

    -- Apply to live views
    viewdesc.apply(liveView, patches)
--]]

local M = {}

-- ── Description format ───────────────────────────────────────────────────
--
-- A view description is a plain table:
--   {
--     tag = "VStack",           -- component name
--     props = { padding = 24 }, -- layout props (no children, no functions)
--     children = { ... },       -- child descriptions
--     key = "unique-id",        -- for stable identity during diffing
--   }
--
-- Special nodes:
--   { tag = "Text", props = { text = "Hello" } }
--   { tag = "__text", value = "raw text" }  -- text node
--   { tag = "__component", fn = functionRef, props = {...} }  -- Lua component

-- ── Build description from XML nodes ──────────────────────────────────────

-- Layout prop names that should be included in descriptions
local LAYOUT_PROPS = {
    "padding", "paddingHorizontal", "paddingVertical", "paddingLeading", "paddingTrailing",
    "spacing", "alignment",
    "width", "height", "minWidth", "minHeight",
    "maxWidth", "maxHeight",
    "flexGrow", "flexShrink", "flexBasis",
    "hidden",
}

local function extractLayoutProps(attrs)
    local props = {}
    if attrs.id then props.id = attrs.id end
    for _, k in ipairs(LAYOUT_PROPS) do
        if attrs[k] then
            local v = attrs[k]
            if v == "true" then v = true
            elseif v == "false" then v = false
            else v = tonumber(v) or v end
            props[k] = v
        end
    end
    return props
end

local function describeNodes(nodes)
    local result = {}
    for _, node in ipairs(nodes) do
        if node.kind == "element" then
            local desc = describeNode(node)
            if desc then table.insert(result, desc) end
        elseif node.kind == "text" then
            local text = node.value:match("^%s*(.-)%s*$")
            if #text > 0 then
                table.insert(result, { tag = "__text", value = text })
            end
        end
    end
    return result
end

function describeNode(node)
    local tag = node.tag
    local attrs = node.attrs
    local children = describeNodes(node.children)

    -- Text/Label
    if tag == "Label" or tag == "Text" then
		local props = extractLayoutProps(attrs)
		props.text = attrs.text or attrs.value or ""
		props.size = attrs.size and tonumber(attrs.size) or nil
		props.weight, props.color, props.key = attrs.weight, attrs.color, attrs.key
        return {
            tag = tag,
            props = props,
            children = children,
        }
    end

    -- Layout containers
    if tag == "VStack" or tag == "HStack" or tag == "HSplit" then
        local props = extractLayoutProps(attrs)
        return {
            tag = tag,
            props = props,
            children = children,
        }
    end

    -- Spacer
    if tag == "Spacer" then
        return {
            tag = tag,
            props = extractLayoutProps(attrs),
            children = {},
        }
    end

    -- Divider
    if tag == "Divider" then
        local props = extractLayoutProps(attrs)
        if attrs.orientation then props.orientation = attrs.orientation end
        return {
            tag = tag,
            props = props,
            children = {},
        }
    end

    -- Button
    if tag == "Button" then
        local props = extractLayoutProps(attrs)
        props.title = attrs.title or attrs.label or ""
        if attrs.systemImage then props.systemImage = attrs.systemImage end
        if attrs.style then props.style = attrs.style end
        return {
            tag = tag,
            props = props,
            children = children,
        }
    end

    -- TextField
    if tag == "TextField" then
        local props = extractLayoutProps(attrs)
        props.value = attrs.value or attrs.text or ""
        props.placeholder = attrs.placeholder or ""
        if attrs.editable ~= nil then props.editable = attrs.editable == "true" end
        return {
            tag = tag,
            props = props,
            children = children,
        }
    end

    -- SystemImage
    if tag == "SystemImage" or tag == "Image" then
        local props = extractLayoutProps(attrs)
        props.name = attrs.name or attrs.symbol or attrs.src or ""
        if attrs.size then props.size = tonumber(attrs.size) end
        if attrs.label then props.accessibilityLabel = attrs.label end
        return {
            tag = tag,
            props = props,
            children = {},
        }
    end

    -- List (simplified — columns become props)
    if tag == "List" then
        local props = extractLayoutProps(attrs)
        props.id = attrs.id
        props.style = attrs.style
        props.header = attrs.header ~= "false"
        props.alternatingRows = attrs.alternatingRows ~= "false"
        props.reorderable = attrs.reorderable == "true"
        props.reorderContainer = attrs.reorderContainer
        props.data = attrs.data
        -- Extract columns from children
        local columns = {}
        for _, c in ipairs(children) do
            if c.tag == "__column" then
                table.insert(columns, c.props)
            end
        end
        props.columns = columns
        return {
            tag = tag,
            props = props,
            children = {},
        }
    end

    -- Column (returns plain table, not a view)
    if tag == "Column" then
        return {
            tag = "__column",
            props = {
                id = attrs.id,
                title = attrs.title or "",
                width = attrs.width and tonumber(attrs.width) or nil,
                alignment = attrs.alignment,
            },
            children = {},
        }
    end

    -- Generic: include all attributes
    local props = extractLayoutProps(attrs)
    for k, v in pairs(attrs) do
        if not props[k] and k ~= "id" then
            props[k] = v
        end
    end
    if attrs.id then props.id = attrs.id end

    return {
        tag = tag,
        props = props,
        children = children,
    }
end

-- ── Generate description from XML ─────────────────────────────────────────

-- Minimal XML parser (same as xml.lua but produces descriptions)
local function parseXMLDesc(src)
    local nodes = {}
    local stack = { { tag = "__root__", attrs = {}, children = nodes } }

    local pos = 1
    local len = #src

    local function current() return stack[#stack] end

    local function pushText(text)
        text = text:match("^%s*(.-)%s*$")
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

        if src:sub(lt, lt + 3) == "<!--" then
            local ce = src:find("-->", lt + 4, true)
            pos = ce and (ce + 3) or (len + 1)
        elseif src:sub(lt + 1, lt + 1) == "/" then
            local gt = src:find(">", lt + 2, true)
            if not gt then error("xml: unclosed closing tag near pos " .. lt) end
            if #stack > 1 then table.remove(stack) end
            pos = gt + 1
        else
            local gt = src:find(">", lt + 1, true)
            if not gt then error("xml: unclosed tag near pos " .. lt) end
            local inner = src:sub(lt + 1, gt - 1)
            local selfClose = inner:sub(-1) == "/"
            if selfClose then inner = inner:sub(1, -2) end

            local tag, rest = inner:match("^([%w_%-%.]+)(.*)$")
            if not tag then error("xml: bad tag near pos " .. lt) end

            local attrs = {}
            for key, val in rest:gmatch('%s+([%w_:%-]+)%s*=%s*"([^"]*)"') do
                attrs[key] = val
            end

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

function M.fromString(src, data)
    local etlua = require("etlua")
    if data then
        local ok, result = pcall(etlua.render, src, data)
        if not ok then error("viewdesc: template error: " .. tostring(result)) end
        src = result
    end
    src = src:gsub("^%s*<%?xml[^?]*%?>%s*", "")
             :gsub("^%s*<!DOCTYPE[^>]*>%s*", "")
    local nodes = parseXMLDesc(src)
    return describeNodes(nodes)[1]
end

function M.fromFile(path, data)
    local f = assert(io.open(path, "r"), "viewdesc: cannot open " .. path)
    local src = f:read("*a")
    f:close()
    if type(data) == "table" then
        data.__baseDir = path:match("^(.-)[^/\\]*$")
    end
    return M.fromString(src, data)
end

-- ── Diffing ───────────────────────────────────────────────────────────────
--
-- Compares two view descriptions and returns a list of patches.
-- Each patch: { op = "create"|"update"|"remove", path = {...}, ... }

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k, v in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function M.diff(old, new, path)
    path = path or {}
    local patches = {}

    if not old and new then
        table.insert(patches, { op = "create", path = path, desc = new })
        return patches
    end

    if old and not new then
        table.insert(patches, { op = "remove", path = path })
        return patches
    end

    -- Both exist: check if tag changed (full replace)
    if old.tag ~= new.tag then
        table.insert(patches, { op = "replace", path = path, desc = new })
        return patches
    end

    -- Same tag: check props
    if not deepEqual(old.props, new.props) then
        table.insert(patches, { op = "update", path = path, props = new.props })
    end

    -- Diff children
    local oldChildren = old.children or {}
    local newChildren = new.children or {}
    local maxLen = math.max(#oldChildren, #newChildren)

    for i = 1, maxLen do
        local childPath = {}
        for _, p in ipairs(path) do table.insert(childPath, p) end
        table.insert(childPath, i)

        local childPatches = M.diff(oldChildren[i], newChildren[i], childPath)
        for _, p in ipairs(childPatches) do
            table.insert(patches, p)
        end
    end

    return patches
end

-- ── Patch application ─────────────────────────────────────────────────────
--
-- Given a live native view and a list of patches, apply them.
-- This is a stub — actual implementation depends on the native bridge.

function M.apply(view, patches)
    -- TODO: implement with bridge._viewSetProps, bridge._viewAddChild, etc.
    -- For now, this is a placeholder showing the API shape.
    for _, patch in ipairs(patches) do
        if patch.op == "update" then
            -- Navigate to the target view using path
            -- Apply prop changes
        elseif patch.op == "create" then
            -- Create new view from description
            -- Insert at path
        elseif patch.op == "remove" then
            -- Remove view at path
        elseif patch.op == "replace" then
            -- Replace view at path with new description
        end
    end
end

-- ── Serialization (for debugging, network transport, etc.) ────────────────

local json = nil -- optional

function M.serialize(desc)
    -- Simple JSON-like serialization (no external deps)
    if type(desc) ~= "table" then return tostring(desc) end
    local parts = {}
    table.insert(parts, "{")
    local first = true
    for k, v in pairs(desc) do
        if not first then table.insert(parts, ",") end
        first = false
        table.insert(parts, '"' .. tostring(k) .. '":')
        if type(v) == "string" then
            table.insert(parts, '"' .. v:gsub('"', '\\"') .. '"')
        elseif type(v) == "table" then
            table.insert(parts, (M.serialize(v)))
        else
            table.insert(parts, tostring(v))
        end
    end
    table.insert(parts, "}")
    return table.concat(parts)
end

return M
