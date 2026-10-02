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
local padLeaf

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

-- Event attributes name controller actions. When a controller supplies
-- actions, a misspelt name fails at render time instead of silently leaving
-- the control unbound; static renders (previews, layout tests) have none.
local function bindActions(props, attrs, names)
    local actions = renderData and renderData.actions
    if not actions then return end
    for _, name in ipairs(names) do
        if attrs[name] then
            local action = actions[attrs[name]]
            if type(action) ~= "function" then
                error("xml: " .. name .. "=\"" .. attrs[name] .. "\" requires a controller action")
            end
            props[name] = action
        end
    end
end

-- SwiftUI `.fixedSize(horizontal:vertical:)`: the axes that keep their
-- content size instead of taking the proposal.
local FIXED_SIZES = { horizontal = true, vertical = true, both = true }

local function layoutProps(attrs)
    local lp = {
        "padding", "paddingHorizontal", "paddingVertical", "paddingLeading", "paddingTrailing", "paddingTop", "paddingBottom",
        "spacing", "alignment", "maxRows", "fixedSize",
        "flexGrow", "flexShrink", "flexBasis",
        "containerRelativeWidth", "hidden", "allowsHitTesting", "background", "tint", "cornerRadius", "clipsToBounds", "ignoresSafeArea", "contentMode", "onClick", "onTap", "onDrag", "onEdgeSwipe",
        "opacity", "scaleEffect", "rotationEffect", "offsetX", "offsetY",
        "help", "dropExternalOnly",
    }
    local props = {}
    for _, k in ipairs(lp) do
        if attrs[k] then props[k] = coerce(attrs[k]) end
    end
    if attrs.fixedSize and not FIXED_SIZES[attrs.fixedSize] then
        error("xml: fixedSize must be horizontal, vertical or both")
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
    bindActions(props, attrs, { "onDrop", "onFileDragChanged" })
    for _, key in ipairs({ "onTap", "onDrag", "onEdgeSwipe" }) do
        if attrs[key] and type(attrs[key]) == "string" and renderData and renderData.actions then
            props[key] = renderData.actions[attrs[key]]
        end
    end
    return props
end

-- SwiftUI applies .padding to any view. Stacks inset their children
-- natively, but a leaf (a label, a paragraph, an image) draws edge to edge in
-- its frame, so a padded leaf is wrapped in a stack that carries the padding
-- and the leaf's expansion. The leaf keeps its id, so refs still reach it.
local paddedLeaves = setmetatable({}, { __mode = "k" })
local PADDING_KEYS = { "padding", "paddingHorizontal", "paddingVertical", "paddingLeading",
    "paddingTrailing", "paddingTop", "paddingBottom" }

padLeaf = function(view, props, ns)
    if type(view) ~= "userdata" or type(ns._hasLayoutAxis) ~= "function" then return view end
    local wrapper = { spacing = 0, alignment = "leading" }
    local padded = false
    for _, key in ipairs(PADDING_KEYS) do
        if props[key] ~= nil then wrapper[key] = props[key]; padded = true end
    end
    if not padded or ns._hasLayoutAxis(view) then return view end
    for _, key in ipairs({ "fillWidth", "fillHeight", "flexGrow", "containerRelativeWidth" }) do
        wrapper[key] = props[key]
    end
    view.containerRelativeWidth = 0
    table.insert(wrapper, view)
    local stack = ns.VStack(wrapper)
    paddedLeaves[stack] = view
    return stack
end

-- ── Node → view compilation ───────────────────────────────────────────────
--
-- refs: table populated during compile; any view with an id="name" attr
-- has its produced view stored as refs[name]. Callers use refs to attach
-- callbacks after rendering without scanning the view tree.

-- While a retained template compiles (xml.mount, xml.reconcile), each element
-- node records the view it produced and renders its callbacks in its own
-- Scope, so the reconciler can replace or remove one node's subtree and
-- dispose exactly the callbacks it owned.
local tracking = false

-- SwiftUI's motion modifiers: metadata the animation engine reads when a
-- transaction inserts, removes or changes the view.
local function applyMotion(view, target, attrs, ns)
    if type(view) ~= "userdata" then return end
    if attrs.transition and ns.transition then ns.transition(view, attrs.transition) end
    if attrs.matchedGeometry and ns.matchedGeometry then
        ns.matchedGeometry(view, attrs.matchedGeometry, attrs.matchedGeometryNamespace)
    end
    if attrs.contentTransition and ns.contentTransition then ns.contentTransition(target, attrs.contentTransition) end
    -- An indefinite symbol effect runs while the view exists; one with a
    -- value plays each time the value changes (see xml.reconcile).
    if attrs.symbolEffect and ns.symbolEffect and not attrs.symbolEffectValue and attrs.symbolEffectActive ~= "false" then
        ns.symbolEffect(target, attrs.symbolEffect, { repeating = true })
    end
end

-- ── Column content templates ──────────────────────────────────────────────
--
-- A <Column>'s child XML is its cell template (SwiftUI `TableColumn { row in
-- ... }`, WPF's DataTemplate). etlua runs once, when the screen renders; an
-- attribute written `{field}` is resolved per row instead. The template is
-- compiled once for each reusable native cell, and the platform applies the
-- bindings natively whenever a cell is given a row, so scrolling runs no Lua.
--
--   {field}             the row's value, typed (a Gauge value stays a number)
--   "Used {a} of {b}"   text interpolation; a missing field reads as empty
--   {!field}            true when the field is missing, false or empty
--   {{                  a literal brace
--
-- There are no expressions: a derived value is a row field the model
-- prepares. A row without the field returns the attribute to the value the
-- view was built with, so a reused cell never shows its previous row.

-- attribute -> { native property, kind, inverted }
local ANY_BINDINGS = {
    hidden = { "hidden", "bool", outer = true },
    opacity = { "opacity", "number", outer = true },
    help = { "toolTip", "string" },
    accessibilityLabel = { "accessibilityLabel", "string" },
    disabled = { "enabled", "bool", inverted = true },
}
local TEXT_BINDING = { "text", "string" }
local SYMBOL_BINDING = { "symbolName", "string" }
local TAG_BINDINGS = {
    Label = { text = TEXT_BINDING, value = TEXT_BINDING, color = { "textColor", "color" } },
    SystemImage = { name = SYMBOL_BINDING, symbol = SYMBOL_BINDING, color = { "contentTintColor", "color" },
        badgeColor = { "badgeColorName", "string" }, appIcon = { "appBundleId", "string" } },
    Gauge = { value = { "doubleValue", "number" }, tint = { "fillColor", "color" } },
    ProgressView = { value = { "doubleValue", "number" } },
}

-- The bindings of the cell being compiled; nil outside a cell template.
local cellBindings

local function parseBinding(value)
    local parts, literal, position = {}, "", 1
    local function fail(reason)
        error("xml: row binding \"" .. value .. "\" " .. reason)
    end
    while position <= #value do
        local open = value:find("{", position, true)
        if not open then
            literal = literal .. value:sub(position)
            break
        end
        literal = literal .. value:sub(position, open - 1)
        if value:sub(open + 1, open + 1) == "{" then
            literal = literal .. "{"
            position = open + 2
        else
            local close = value:find("}", open, true)
            if not close then fail("has an unclosed brace") end
            local negate, field = value:sub(open + 1, close - 1):match("^(!?)([%a_][%w_]*)$")
            if not field then fail("must name one row field; prepare derived values in the model") end
            if literal ~= "" then table.insert(parts, literal); literal = "" end
            table.insert(parts, { field = field, negate = negate == "!" })
            position = close + 1
        end
    end
    if literal ~= "" then table.insert(parts, literal) end
    return parts
end

-- Splits a template node's attributes into the static ones its constructor
-- takes and the bindings applied per row.
local function splitBindings(node)
    local attrs, bound = {}, {}
    for key, value in pairs(node.attrs) do
        if type(value) == "string" and value:find("{", 1, true) then
            local parts = parseBinding(value)
            local whole = #parts == 1 and type(parts[1]) == "table"
            local fields = 0
            for _, part in ipairs(parts) do if type(part) == "table" then fields = fields + 1 end end
            if fields == 0 then
                attrs[key] = parts[1] or ""
            else
                local spec = (TAG_BINDINGS[node.tag] or {})[key] or ANY_BINDINGS[key]
                if not spec then
                    error("xml: <" .. node.tag .. "> cannot bind " .. key .. " to a row field")
                end
                local kind, negate = spec[2], false
                if kind ~= "string" and not whole then
                    error("xml: <" .. node.tag .. "> " .. key .. "=\"" .. value .. "\" must be one {field}")
                end
                for index, part in ipairs(parts) do
                    if type(part) == "table" then
                        if part.negate and kind ~= "bool" then
                            error("xml: <" .. node.tag .. "> " .. key .. "=\"" .. value .. "\": {!field} applies to true/false attributes")
                        end
                        negate = part.negate
                        parts[index] = { field = part.field }
                    end
                end
                if spec.inverted then negate = not negate end
                table.insert(bound, { key = spec[1], kind = kind, parts = parts, negate = negate, outer = spec.outer })
            end
        else
            attrs[key] = value
        end
    end
    return attrs, bound
end

local compile

-- The factory the platform calls when it has no cell to reuse. Returns the
-- template's root view and its bindings.
local function columnTemplate(node, ns, registry)
    local roots = {}
    for _, child in ipairs(node.children) do
        if child.kind == "element" then table.insert(roots, child) end
    end
    if #roots == 0 then return nil end
    if #roots > 1 then
        error("xml: <Column> content must be one view; wrap the cell in a stack")
    end
    -- Mistakes in a binding fail the render, not the first scroll.
    local function validate(element)
        if element.kind ~= "element" then return end
        splitBindings(element)
        for _, child in ipairs(element.children) do validate(child) end
    end
    validate(roots[1])
    local templateData = renderData
    return function()
        local previousData, previousTracking, previousBindings = renderData, tracking, cellBindings
        renderData, tracking, cellBindings = templateData, false, {}
        local ok, views = pcall(compile, roots, ns, registry, {})
        local bindings = cellBindings
        renderData, tracking, cellBindings = previousData, previousTracking, previousBindings
        if not ok then error(views, 0) end
        if type(views[1]) ~= "userdata" then
            error("xml: <Column> content must render one native view")
        end
        return views[1], bindings
    end
end

compile = function(nodes, ns, registry, refs)
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
			local templated = node.tag == "Column"
			local attrs, bound = node.attrs, nil
			if cellBindings then attrs, bound = splitBindings(node) end
			local children
			if templated then
				-- Absent for a text column; Column.collect takes the factory.
				children = { template = columnTemplate(node, ns, registry) }
			elseif lazy then
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
			end
			local nodeScope
			if tracking then
				nodeScope = ns.Scope.new()
				local parent = ns.Scope.current()
				if parent then
					parent:add(nodeScope)
					-- Callbacks this node fires register what they start in
					-- the template's scope (see lua_reg_push).
					nodeScope.enclosing = parent.enclosing or parent
				end
			end
			local view
			if nodeScope then
				if not children then children = ns.Scope.withScope(nodeScope, compile, node.children, ns, registry, refs) end
				view = ns.Scope.withScope(nodeScope, handler, ns, attrs, children)
			else
				if not children then children = compile(node.children, ns, registry, refs) end
				view = handler(ns, attrs, children)
			end
			applyMotion(view, paddedLeaves[view] or view, attrs, ns)
			-- SwiftUI's `.accessibilityLabel` applies to any view: tags whose
			-- constructor does not take the label still carry it.
			if attrs.accessibilityLabel and type(view) == "userdata" then
				local target = paddedLeaves[view] or view
				if target.accessibilityLabel ~= attrs.accessibilityLabel then
					target.accessibilityLabel = attrs.accessibilityLabel
				end
			end
			if bound and #bound > 0 then
				if type(view) ~= "userdata" then
					error("xml: <" .. node.tag .. "> cannot bind row fields; it renders no view")
				end
				for _, binding in ipairs(bound) do
					binding.view = binding.outer and view or paddedLeaves[view] or view
					binding.outer = nil
					table.insert(cellBindings, binding)
				end
			end
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
				if tracking then
					node.view, node.target, node.scope = view, paddedLeaves[view] or view, nodeScope
				end
				if node.attrs.id and type(view) == "userdata" then
					local target = paddedLeaves[view] or view
					refs[node.attrs.id] = target
					-- Keep the declarative identity on the native view as well as
					-- in the returned refs table. Diagnostics and accessibility
					-- tooling can then locate the same semantic node without
					-- depending on child order or implementation classes.
					pcall(function()
						target.accessibilityIdentifier = node.attrs.id
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
            labelWeight = "str",
            labelSize = "num",
            indicatorWidth = "num",
            indicatorSpacing = "num",
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
        transform = function(props, attrs)
            bindActions(props, attrs, { "onChange" })
        end,
    },
    ProgressView = {
        constructor = "ProgressView",
        props = {
            value = "num",
            indeterminate = "bool",
            tint = "str",
            controlSize = "str",
        },
    },
    -- SwiftUI Gauge (linear capacity style).
    Gauge = {
        constructor = "Gauge",
        props = { value = "num", minValue = "num", maxValue = "num", tint = "str", thickness = "num", accessibilityLabel = "str" },
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
            scrollOnKeyboard = "bool",
            scrollDismissesKeyboard = "str",
            scrollTargetBehavior = "str",
        },
    },
    -- SwiftUI Charts SectorMark: a pie or donut built from native arcs.
    -- Non-mark children are centered over the chart.
    SectorChart = {
        constructor = "SectorChart",
        children = "array",
        props = { innerRadius = "num", angularInset = "num", depth = "num", shadow = "bool", scalable = "bool", diameter = "num", accessibilityLabel = "str" },
        -- New marks move the existing arcs, like SwiftUI Charts, instead of
        -- rebuilding the chart (see ui/sectors.lua).
        updateRecords = function(view, records) return require("ui.sectors").update(view, records) end,
        -- Attributes the marks are laid out with; a change lays them out again.
        recordLayout = { "innerRadius", "angularInset" },
        transform = function(props, attrs)
            bindActions(props, attrs, { "onSelect", "onHover", "onCenter", "onBack", "dragItem" })
        end,
    },
    -- `ring` 2+ with a `parent` id draws a sunburst level inside the parent.
    SectorMark = {
        kind = "record", flag = "__sectorMark",
        props = { id = "str", value = "num", color = "str", label = "str", ring = "num", parent = "str", opacity = "num" },
    },
    -- SwiftUI SceneView over SceneKit. Its records are the scene graph and
    -- reconcile in place by id (see src/shared/scene_view.m).
    SceneView = {
        constructor = "SceneView",
        children = "array",
        props = { background = "str", showsStatistics = "bool" },
        updateRecords = function(view, records) return require("AppKit").sceneGraph(view, records) end,
        transform = function(props, attrs)
            bindActions(props, attrs, { "onKey", "onFrame", "onSwipe", "onTap" })
        end,
    },
    -- A scene node: a model file or a primitive geometry, posed by
    -- position/rotation (degrees)/scale, with idle `spin` (degrees per
    -- second about y, or "x y z") and `bob` behaviours and an insertion/removal `transition` (pop, rise, fade).
    -- Child records hang from it and move with it.
    Node = {
        kind = "record", children = "items",
        props = { id = "str", model = "str", geometry = "str", position = "str", rotation = "str", scale = "str",
            width = "num", height = "num", length = "num", radius = "num", chamfer = "num", color = "str",
            hidden = "bool", opacity = "num", castsShadow = "bool", spin = "str", bob = "num", bobPeriod = "num",
            transition = "str", lookAt = "str" },
        transform = function(rec) rec.sceneKind = "node" end,
    },
    -- The first camera is the view's point of view. `fieldOfViewAxis`
    -- "horizontal" keeps the width framed whatever the view's shape.
    Camera = {
        kind = "record", children = "items",
        props = { id = "str", position = "str", rotation = "str", lookAt = "str", fieldOfView = "num", fieldOfViewAxis = "str",
            zNear = "num", zFar = "num", orthographicScale = "num" },
        transform = function(rec) rec.sceneKind = "camera" end,
    },
    -- `type` is directional (default), ambient, omni or spot.
    Light = {
        kind = "record", children = "items",
        props = { id = "str", type = "str", position = "str", rotation = "str", lookAt = "str", intensity = "num",
            color = "str", castsShadow = "bool", shadowRadius = "num", shadowOpacity = "num" },
        transform = function(rec) rec.sceneKind = "light" end,
    },
    -- Squarified treemap; nested nodes name their `parent`.
    Treemap = {
        constructor = "Treemap",
        children = "array",
        props = { selected = "str", accessibilityLabel = "str" },
        transform = function(props, attrs)
            bindActions(props, attrs, { "onSelect", "onHover", "onBack", "dragItem" })
        end,
    },
    TreemapNode = {
        kind = "record", flag = "__treemapNode",
        props = { id = "str", parent = "str", value = "num", color = "str", label = "str", detail = "str", hatched = "bool" },
    },
    Arc = {
        constructor = "Arc",
        props = {
            startAngle = "num",
            endAngle = "num",
            lineWidth = "num",
            stroke = "str",
            strokeAlpha = "num",
            lineCap = "str",
        },
    },
    SafeAreaInset = {
        constructor = "SafeAreaInset",
        children = "array",
        props = { edge = "str", minimumBottomInset = "num", keyboardBottomInset = "num",
            horizontalInset = "num", matchBottomHorizontalInset = "bool" },
    },

    -- Text & Typography
    Label = {
        constructor = "Text",
        positional  = { "text", "value", default = "" },
		props = {
            size       = "num",
            weight     = "str",
			design     = "str",
			fontName   = "str",
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
            monospacedDigit = "bool",
            smallCaps = "bool",
            minimumScaleFactor = "num",
        },
        transform = function(props, a)
            if a.lines and (num(a.lines) or 0) > 1 then
                props.lineBreakMode = 0
            end
        end,
    },
    -- Long-form prose: selectable, with leading, hyphenation and drop caps.
    Paragraph = {
        constructor = "Paragraph",
        positional  = { "text", "value", default = "" },
        props = {
            size = "num", weight = "str", design = "str", fontName = "str", italic = "bool",
            smallCaps = "bool", color = "str", lineSpacing = "num", alignment = "str",
            hyphenation = "bool", selectable = "bool", accessibilityLabel = "str",
            figure = "str", figureLines = "num",
            revealedCharacters = "num", linkColor = "str",
        },
        -- <Hyperlink> children mark the words a reader can act on.
        collect = function(props, children)
            if #children == 0 then return end
            props.links = {}
            for _, child in ipairs(children) do
                if type(child) ~= "table" or not child.__hyperlink then
                    error("xml: <Paragraph> accepts only <Hyperlink> children")
                end
                table.insert(props.links, child)
            end
        end,
        updateRecords = function(view, records)
            for _, name in ipairs({ "UIKitNative", "AppKitNative" }) do
                local ok, native = pcall(require, name)
                if ok and type(native) == "table" and type(native._paragraphSetLinks) == "function" then
                    native._paragraphSetLinks(view, records)
                    return true
                end
            end
            return false
        end,
    },
    -- A run of a <Paragraph> that opens a menu when tapped (WPF Hyperlink
    -- inside a TextBlock). `location` counts characters from 0 as
    -- `utf8.len` does; <MenuItem> children are what the reader can do.
    Hyperlink = {
        kind = "record",
        flag = "__hyperlink",
        props = { location = "num", length = "num", label = "str" },
        collect = function(rec, children)
            rec.items = children
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
    CodeView = {
        constructor = "CodeView",
        props = {
            text = { aliases = { "value" }, default = "", type = "str" },
            language = { default = "lua", type = "str" },
            syntaxRules = "str",
            size = "num",
            wrapMode = "bool",
            drawsBackground = "bool",
        },
        transform = function(props, attrs)
            if renderData and attrs.syntaxRules then props.syntaxRules = renderData[attrs.syntaxRules] end
        end,
    },
    SearchField = {
        constructor = "SearchField",
        props = {
            value = { aliases = { "text" }, default = "", type = "str" },
            placeholder = { default = "Search", type = "str" },
            accessibilityLabel = "str",
            defaultFocus = "bool",
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
			accessibilityLabel = "str",
			defaultFocus = "bool",
        },
        transform = function(props, attrs)
            if renderData and renderData.actions then
                if attrs.onChange then props.onChange = renderData.actions[attrs.onChange] end
                if attrs.onCommand then props.onCommand = renderData.actions[attrs.onCommand] end
                if attrs.onFocus then props.onFocus = renderData.actions[attrs.onFocus] end
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
			keyboardShortcut = "str",
			controlSize = "str",
			tint = "str",
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
			style = "str",
			tint = "str",
			systemImage = "str",
			symbolSize = "num",
        },
		transform = function(props, attrs)
			bindActions(props, attrs, { "onChange" })
		end,
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
			imagePath = "str",
			style = "str",
			symbolSize = "num",
			accessibilityLabel = "str",
		},
        collect = function(props, children)
            props.items = children
        end,
    },
    -- A menu command. Nested <MenuItem> children form a submenu (WPF
    -- MenuItem). In the menu bar, `keyEquivalent` plus `modifiers`
    -- ("command,shift") is SwiftUI's `.keyboardShortcut`, and `validate`
    -- names an action returning `enabled, checked` whenever AppKit validates
    -- the item.
    MenuItem = {
        kind = "record",
        flag = "__menuItem",
        props = {
            title = { aliases = { "label" }, default = "", type = "str" },
            systemImage = "str",
			imagePath = "str",
            role = "str",
            keyEquivalent = "str",
            modifiers = "str",
            checked = "bool",
            disabled = "bool",
        },
        collect = function(rec, children)
            if #children > 0 then rec.items = children end
        end,
		transform = function(props, attrs)
			if attrs.action and renderData and renderData.actions then
				props.action = renderData.actions[attrs.action]
			end
			bindActions(props, attrs, { "validate" })
		end,
    },
    Separator = {
        kind = "record",
        flag = "__menuItem",
        transform = function(props) props.separator = true end,
    },
    -- The application menu bar (SwiftUI `.commands`). Only a <Window> may
    -- carry it; the app menu, Hide and Quit items take `appName`.
    Commands = {
        kind = "record",
        flag = "__commands",
        props = { appName = "str" },
        collect = function(rec, children)
            rec.groups, rec.menus, rec.helpTopics = {}, {}, {}
            for _, child in ipairs(children) do
                if type(child) ~= "table" then
                    error("xml: <Commands> accepts CommandGroup, CommandMenu and HelpTopic")
                elseif child.__commandGroup then table.insert(rec.groups, child)
                elseif child.__commandMenu then table.insert(rec.menus, child)
                elseif child.__helpTopic then table.insert(rec.helpTopics, child)
                else error("xml: <Commands> accepts CommandGroup, CommandMenu and HelpTopic") end
            end
        end,
    },
    -- Edits a standard group: `replacing`, `before` or `after` names a
    -- SwiftUI CommandGroupPlacement such as "appSettings" or "sidebar".
    CommandGroup = {
        kind = "record",
        flag = "__commandGroup",
        children = "items",
        transform = function(rec, attrs)
            for _, position in ipairs({ "replacing", "before", "after" }) do
                if attrs[position] then
                    if rec.placement then error("xml: <CommandGroup> takes one of replacing, before or after") end
                    rec.placement, rec.position = attrs[position], position
                end
            end
            if not rec.placement then error("xml: <CommandGroup> requires replacing, before or after") end
        end,
    },
    CommandMenu = {
        kind = "record",
        flag = "__commandMenu",
        children = "items",
        props = { title = "str" },
    },
    -- A result offered by the Help menu's search field beside matching menu
    -- items; `keywords` widen the match and `action` opens the topic.
    HelpTopic = {
        kind = "record",
        flag = "__helpTopic",
        props = { title = "str", keywords = "str" },
        transform = function(rec, attrs) bindActions(rec, attrs, { "action" }) end,
    },
    -- Child controls are SwiftUI's `actions:` slot, beneath the message.
    ContentUnavailable = {
        constructor = "ContentUnavailable",
        children = "array",
        props = {
            title = "str",
            systemImage = "str",
            description = "str",
            descriptionAlignment = "str",
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
			tint                    = "str",
			style                   = "str",
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
            props.darkPath = a.darkPath
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
            startPoint = "str",
            endPoint = "str",
        },
        -- colors="systemIndigo,systemPink": a comma-separated list, in order.
        transform = function(props, a)
            if not a.colors then return end
            props.colors = {}
            for name in a.colors:gmatch("[^,%s]+") do table.insert(props.colors, name) end
        end,
    },
    MeshPoint = {
        kind = "record", flag = "__meshPoint",
        props = { x = "num", y = "num", red = "num", green = "num", blue = "num", alpha = "num" },
    },
    MeshGradient = {
        constructor = "MeshGradient", children = "array",
        props = { width = "num", height = "num", animated = "bool" },
        collect = function(props, children)
            if #children == 0 then return end
            props.points, props.colors = {}, {}
            for _, child in ipairs(children) do
                if not child.__meshPoint then error("xml: <MeshGradient> accepts only <MeshPoint> children") end
                table.insert(props.points, { child.x, child.y })
                table.insert(props.colors, {
                    red = child.red, green = child.green, blue = child.blue, alpha = child.alpha,
                })
            end
            for index = #props, 1, -1 do props[index] = nil end
        end,
        transform = function(props)
            -- width and height are mesh grid dimensions, not view frame dimensions.
            props.fixedWidth, props.fixedHeight = nil, nil
        end,
    },
    ShaderView = {
        constructor = "ShaderView",
        props = { source = "str", ["function"] = "str", layers = "num" },
        collect = function(props, children)
            local sources = {}
            for _, child in ipairs(children) do
                if type(child) ~= "table" or not child.__shaderSource then
                    error("xml: <ShaderView> accepts only <ShaderSource> children")
                end
                table.insert(sources, { path = child.path, code = child.code })
            end
            if #sources > 0 then props.sources = sources end
        end,
    },
    -- One chunk of a linked <ShaderView> program: a file or a code snippet.
    ShaderSource = {
        kind = "record",
        flag = "__shaderSource",
        props = { path = "str", code = "str" },
    },
    TimelineView = {
        constructor = "TimelineView", children = "content",
        props = { schedule = "str" },
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
            loadingKey = "str",
            controlSize = "str",
            buttonSymbol = "str",
            buttonMenu = "bool",
            badgeKey = "str",
            labelStyle = "str",
            helpKey = "str",
        },
        collect = function(props, children)
            -- Child XML is the column's cell template; see "Column content
            -- templates" above.
            props.template = children.template
            for key, field in pairs({badgeKey = "badge", loadingKey = "loading", controlSize = "controlSize", buttonSymbol = "button", buttonMenu = "buttonMenu", badgeColorKey = "badgeColor", appIconKey = "appIcon", subtitleKey = "secondary", fileIconKey = "fileIcon", imageKey = "image", imageColorKey = "imageColor", imageSize = "imageSize", labelStyle = "labelStyle", helpKey = "help"}) do
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
            scrollDisabled  = "bool",
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
            rowMenu = "str",
            dragKey = "str",
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
            bindActions(props, attrs, { "onSelect", "onActivate", "onSort", "onColumnButton", "rowMenu" })
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
            placement = "str",
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
    -- A navigation destination. One <Toolbar> child carries its toolbar items
    -- (SwiftUI .toolbar placements); exactly one view child is its content.
    Page = {
        constructor = "Page",
        props = {
            title = "str",
            hidesTabBar = "bool",
            hidesNavigationBar = "bool",
            titleDisplayMode = "str",
            backButtonDisplayMode = "str",
        },
        collect = function(props, children)
            for _, child in ipairs(children) do
                if type(child) == "table" and child.__toolbar then
                    if props.toolbar then error("xml: <Page> accepts one <Toolbar>") end
                    props.toolbar = child.items or {}
                elseif type(child) == "userdata" then
                    if props.content then error("xml: <Page> accepts one content view") end
                    props.content = child
                end
            end
            if not props.content then error("xml: <Page> requires one content view") end
        end,
        transform = function(props, attrs)
            bindActions(props, attrs, { "onDisappear" })
            local actions = renderData and renderData.actions
            for _, item in ipairs(props.toolbar or {}) do
                if type(item.action) == "string" and actions then
                    local action = actions[item.action]
                    if type(action) ~= "function" then
                        error("xml: ToolbarItem action=\"" .. item.action .. "\" requires a controller action")
                    end
                    item.action = action
                end
            end
        end,
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
            subtitle                   = "str",
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
            hideTitle                  = "bool",
            transparentTitlebar        = "bool",
            level                      = "str",
            aspectRatio                = "num",
            onClose                    = "str",
            visible                    = "bool",
            sidebarWidth               = "num",
            detailWidth                = "num",
            contentWidth               = "num",
            toolbarContentDividerAfter = "str",
            onBack                     = "str",
            onForward                  = "str",
        },
        collect = function(cfg, children)
            local toolbarItems, contentViews = {}, {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__commands then
                    if cfg.commands then error("xml: <Window> accepts one <Commands>") end
                    cfg.commands = c
                elseif type(c) == "table" and c.__toolbar then
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
        transform = function(cfg, attrs)
            -- Mouse back/forward buttons and horizontal swipes.
            cfg.onBack, cfg.onForward, cfg.onClose = nil, nil, nil
            bindActions(cfg, attrs, { "onBack", "onForward", "onClose" })
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
        transform = function(props, attrs)
            bindActions(props, attrs, { "onChange" })
        end,
        collect = function(props, children)
            local tabs = {}
            for _, c in ipairs(children) do
                if type(c) == "table" and c.__tab then
                    table.insert(tabs, c)
                elseif type(c) == "table" and c.__tabAccessory then
                    if props.accessory then error("xml: <TabView> accepts one <TabAccessory>") end
                    props.accessory = c
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
    -- SwiftUI tabViewBottomAccessory: one view shown above the tab bar.
    TabAccessory = {
        kind = "record", flag = "__tabAccessory",
        props = { hidden = "bool" },
        collect = function(props, children)
            if #children ~= 1 then error("xml: <TabAccessory> requires one view") end
            props.content = children[1]
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
            -- SwiftUI Tab(role: .search): iOS 26 sets it apart from the bar.
            role        = "str",
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

        return padLeaf(ctor(props), props, ns)
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
        -- A failed partial must fail its caller; returning nil would print
        -- "nil" into the parent template and hide the error.
        local rendered, err = renderTemplate(src, data, fullPath)
        if rendered == nil then error("partial " .. fullPath .. ": " .. tostring(err), 0) end
        return rendered
    end

    return ctx
end

-- ── Public API ────────────────────────────────────────────────────────────

local registry = makeRegistry()
local M = {}

-- Component tags (ui/component.lua) become the elements their templates
-- render before anything is compiled or reconciled, so the rest of the
-- renderer only ever sees the vocabulary.
local function expandComponents(nodes, description)
    return require("ui.component").expand(nodes, description.data and description.data.__baseDir,
        function(tag) return registry[tag] ~= nil end)
end

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
        return compile(expandComponents(parseXML(description.source), description), ns, registry, refs)
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

-- ── Retained reconciliation ──────────────────────────────────────────────
--
-- A retained template (ui/template.lua) mounts once and then reconciles each
-- new description against the mounted node tree, like SwiftUI's view graph:
--
--   * nodes match by tag and `id` (or `key`), otherwise by tag and order;
--   * a matched node whose changed attributes can be applied to its view in
--     place keeps its native view, state and focus;
--   * stacks insert, move and remove children individually; any other node
--     whose structure changed is rebuilt and replaces the old one;
--   * everything happens inside the current animation transaction, so
--     changes animate and inserted or removed views play their transitions;
--     a node with `animation="…"` animates the update when its
--     `animationValue` changed, like SwiftUI's `.animation(_:value:)`.
--
-- Planning builds new subtrees and validates every change first; nothing on
-- screen changes if planning fails, so a render error keeps the old view.

local function elements(list)
    local result = {}
    for _, child in ipairs(list) do if child.kind == "element" then table.insert(result, child) end end
    return result
end

local function textOf(node)
    local parts = {}
    for _, child in ipairs(node.children) do if child.kind == "text" then table.insert(parts, child.value) end end
    return table.concat(parts)
end

local function identity(node) return node.attrs.id or node.attrs.key end

-- Stacks whose native subviews are exactly their element children, in order.
local CONTAINERS = { VStack = true, HStack = true, ZStack = true, FlowStack = true }

-- Attributes that only describe animation; changing them patches metadata.
local MOTION_ATTRS = { animation = true, animationValue = true, key = true }

local function hasProperty(view, name)
    local ok, value = pcall(function() return view[name] end)
    return ok and value ~= nil
end

local function setter(name, convert)
    return function(view, value, ns)
        if not hasProperty(view, name) then return nil end
        local converted = convert and convert(value, ns) or value
        return function() view[name] = converted end
    end
end

local function number(fallback) return function(v) return v == nil and fallback or num(v) end end

-- Attributes applied to the view the parent holds (a padded leaf's wrapper).
local OUTER = {
    hidden = function(view, v) return function() view.hidden = v ~= nil and bool(v) end end,
    opacity = setter("opacity", number(1)),
    scaleEffect = setter("scaleEffect", number(1)),
    rotationEffect = setter("rotationEffect", number(0)),
    offsetX = setter("offsetX", number(0)),
    offsetY = setter("offsetY", number(0)),
    cornerRadius = setter("cornerRadius", number(0)),
    background = function(view, v, ns)
        local color = v and ns.Color(v) or nil
        return function() view.backgroundColor = color end
    end,
    transition = function(view, v, ns) return function() ns.transition(view, v) end end,
    matchedGeometry = function(view, v, ns, attrs)
        return function() ns.matchedGeometry(view, v, attrs.matchedGeometryNamespace) end
    end,
}
OUTER.matchedGeometryNamespace = function(view, _, ns, attrs)
    return function() ns.matchedGeometry(view, attrs.matchedGeometry, attrs.matchedGeometryNamespace) end
end

-- Attributes applied to the view the tag produced.
local TEXT = setter("text", function(v) return v or "" end)
local INNER = {
    contentTransition = function(view, v, ns) return function() ns.contentTransition(view, v) end end,
    disabled = function(view, v)
        if not hasProperty(view, "enabled") then return nil end
        return function() view.enabled = not (v ~= nil and bool(v)) end
    end,
    -- VoiceOver text often carries live values (a chart's totals); it
    -- updates in place like SwiftUI's `.accessibilityLabel`.
    accessibilityLabel = function(view, v) return function() view.accessibilityLabel = v or "" end end,
    symbolEffect = function() return function() end end,
    symbolEffectActive = function() return function() end end,
    symbolEffectValue = function() return function() end end,
}
local TAG_INNER = {
    Label = { text = TEXT, value = TEXT },
    Paragraph = { text = TEXT, value = TEXT,
        revealedCharacters = setter("revealedCharacters", number(-1)) },
    TextField = { text = TEXT, value = TEXT },
    Button = { title = setter("title", function(v) return v or "" end), label = setter("title", function(v) return v or "" end) },
    ProgressView = { value = function(view, v)
        for _, name in ipairs({ "doubleValue", "progress" }) do
            if hasProperty(view, name) then return function() view[name] = num(v) or 0 end end
        end
    end },
    Gauge = { value = setter("doubleValue", number(0)) },
    Slider = { value = setter("value", number(0)) },
    Picker = { value = function(view, v)
        for _, name in ipairs({ "selectedSegment", "selectedSegmentIndex" }) do
            if hasProperty(view, name) then return function() view[name] = num(v) or 0 end end
        end
    end },
    -- An arc moves to new angles in place, so a change of value animates
    -- like SwiftUI interpolating a trimmed shape.
    Arc = {
        startAngle = setter("startAngle", number(0)),
        endAngle = setter("endAngle", number(0)),
        lineWidth = setter("lineWidth", number(0)),
        strokeAlpha = setter("strokeAlpha", number(1)),
        stroke = setter("stroke"),
        lineCap = setter("lineCap"),
    },
    -- The chart lays its marks out again with these (see `recordLayout`).
    SectorChart = {
        innerRadius = function(view, v) return function() require("ui.sectors").configure(view, { innerRadius = num(v) or 0 }) end end,
        angularInset = function(view, v) return function() require("ui.sectors").configure(view, { angularInset = num(v) or 0 }) end end,
    },
}

-- Layout attributes a view reads from itself. Padding needs a stack (a
-- padded leaf is wrapped when it is built); dimensions are rewritten
-- together because width, maxWidth="infinity" and flex interact.
local DIMENSIONS = { width = true, height = true, minWidth = true, minHeight = true, maxWidth = true, maxHeight = true }
local STACK_LAYOUT = { padding = true, paddingHorizontal = true, paddingVertical = true, paddingLeading = true,
    paddingTrailing = true, paddingTop = true, paddingBottom = true, spacing = true, alignment = true }
local FLEX = { flexGrow = true, flexShrink = true, flexBasis = true }

local function layoutPatch(node, attrs, changed, ns)
    local view = node.view
    local isStack = type(ns._hasLayoutAxis) == "function" and ns._hasLayoutAxis(view)
    local ops, dimensions = {}, false
    for key in pairs(changed) do
        if STACK_LAYOUT[key] then
            if not isStack or attrs[key] == nil then return nil end
            local value = coerce(attrs[key])
            table.insert(ops, function() view[key] = value end)
        elseif key == "fixedSize" then
            local value = attrs.fixedSize
            if value ~= nil and not FIXED_SIZES[value] then return nil end
            table.insert(ops, function() view.fixedSize = value end)
        elseif FLEX[key] then
            if node.view ~= node.target then return nil end
            local value = attrs[key] and num(attrs[key])
            if key == "flexShrink" then value = value or 1 elseif key == "flexGrow" then value = value or 0 end
            table.insert(ops, function() view[key] = value end)
        elseif DIMENSIONS[key] then
            if node.view ~= node.target then return nil end
            dimensions = true
        end
    end
    if dimensions then
        local props = layoutProps(attrs)
        table.insert(ops, function()
            view.fixedWidth, view.fixedHeight = props.fixedWidth, props.fixedHeight
            view.minWidth, view.minHeight = props.minWidth or 0, props.minHeight or 0
            view.maxWidth, view.maxHeight = props.maxWidth, props.maxHeight
            view.fillWidth, view.fillHeight = props.fillWidth == true, props.fillHeight == true
        end)
    end
    return ops
end

-- Operations that apply a node's changed attributes, or nil when a change
-- cannot be applied in place and the node must be rebuilt.
local function attributePatch(old, new, ns)
    local changed = {}
    for key, value in pairs(old.attrs) do if new.attrs[key] ~= value then changed[key] = true end end
    for key, value in pairs(new.attrs) do if old.attrs[key] ~= value then changed[key] = true end end
    local ops, layout = {}, {}
    local tagInner = TAG_INNER[new.tag] or {}
    for key in pairs(changed) do
        local value = new.attrs[key]
        local plan
        if MOTION_ATTRS[key] then
            plan = function() end
        elseif OUTER[key] then
            plan = OUTER[key](old.view, value, ns, new.attrs)
        elseif tagInner[key] then
            plan = tagInner[key](old.target, value, ns, new.attrs)
        elseif INNER[key] then
            plan = INNER[key](old.target, value, ns, new.attrs)
        elseif STACK_LAYOUT[key] or FLEX[key] or DIMENSIONS[key] then
            layout[key] = true
            plan = function() end
        end
        if not plan then return nil end
        table.insert(ops, plan)
    end
    if next(layout) then
        local layoutOps = layoutPatch(old, new.attrs, layout, ns)
        if not layoutOps then return nil end
        for _, op in ipairs(layoutOps) do table.insert(ops, op) end
    end
    -- A discrete symbol effect plays when its value changes.
    if changed.symbolEffectValue and new.attrs.symbolEffect and ns.symbolEffect then
        table.insert(ops, function() ns.symbolEffect(old.target, new.attrs.symbolEffect) end)
    elseif (changed.symbolEffect or changed.symbolEffectActive) and ns.symbolEffect and not new.attrs.symbolEffectValue then
        table.insert(ops, function()
            ns.symbolEffect(old.target, nil)
            if new.attrs.symbolEffect and new.attrs.symbolEffectActive ~= "false" then
                ns.symbolEffect(old.target, new.attrs.symbolEffect, { repeating = true })
            end
        end)
    end
    return ops, changed
end

local reconcileNode

-- Builds a new node's subtree (without inserting it).
local function build(node, ns, plan)
    local views = compile({ node }, ns, registry, {})
    if #views ~= 1 or type(views[1]) ~= "userdata" or node.view ~= views[1] then
        if node.scope then node.scope:dispose() end
        error("xml: <" .. node.tag .. "> must render one native view to be reconciled")
    end
    table.insert(plan.built, node)
    return node
end

local function disposeNode(node)
    if node.scope then node.scope:dispose() end
end

local function isRecord(node)
    local entry = TAG_SCHEMA[node.tag]
    return entry ~= nil and entry.kind == "record"
end

local function sameRecords(oldRecords, newRecords, ns)
    if #oldRecords ~= #newRecords then return false end
    for index, record in ipairs(newRecords) do
        if not reconcileNode(oldRecords[index], record, ns, { ops = {}, removals = {}, built = {} }, true) then return false end
    end
    return true
end

-- A view whose schema entry has `updateRecords(view, records)` takes new
-- record children (chart marks) in place; its view children reconcile as
-- usual. Returns nil when the tag has no such hook.
local function reconcileRecordsInPlace(old, new, ns, plan)
    local entry = TAG_SCHEMA[old.tag]
    if not (entry and entry.updateRecords) then return nil end
    local oldRecords, oldViews, newRecords, newViews = {}, {}, {}, {}
    for _, child in ipairs(elements(old.children)) do table.insert(isRecord(child) and oldRecords or oldViews, child) end
    for _, child in ipairs(elements(new.children)) do table.insert(isRecord(child) and newRecords or newViews, child) end
    if #oldViews ~= #newViews then return false end
    for index, child in ipairs(newViews) do
        if not reconcileNode(oldViews[index], child, ns, plan) then return false end
    end
    local relayout = false
    for _, key in ipairs(entry.recordLayout or {}) do
        if old.attrs[key] ~= new.attrs[key] then relayout = true end
    end
    if relayout or not sameRecords(oldRecords, newRecords, ns) then
        local records = compile(newRecords, ns, registry, {})
        local view = old.target
        table.insert(plan.ops, function()
            if not entry.updateRecords(view, records) then error("xml: <" .. old.tag .. "> could not take new records in place") end
        end)
    end
    return true
end

local function reconcileChildren(old, new, ns, plan)
    local oldChildren, newChildren = elements(old.children), elements(new.children)
    if textOf(old) ~= textOf(new) then return false end
    local inPlace = reconcileRecordsInPlace(old, new, ns, plan)
    if inPlace ~= nil then return inPlace end
    for _, child in ipairs(oldChildren) do
        if type(child.view) ~= "userdata" then
            -- Records (columns, marks, options) configure their parent.
            if #oldChildren ~= #newChildren then return false end
            for index, other in ipairs(newChildren) do
                if not reconcileNode(oldChildren[index], other, ns, plan, true) then return false end
            end
            return true
        end
    end
    if not CONTAINERS[old.tag] then
        if #oldChildren ~= #newChildren then return false end
        for index, child in ipairs(newChildren) do
            if not reconcileNode(oldChildren[index], child, ns, plan) then return false end
        end
        return true
    end
    local keyed, ordered, used = {}, {}, {}
    for _, child in ipairs(oldChildren) do
        local id = identity(child)
        if id then keyed[child.tag .. "#" .. id] = child
        else ordered[child.tag] = ordered[child.tag] or {}; table.insert(ordered[child.tag], child) end
    end
    local results = {}
    for index, child in ipairs(newChildren) do
        local id, match = identity(child), nil
        if id then match = keyed[child.tag .. "#" .. id]
        elseif ordered[child.tag] then match = table.remove(ordered[child.tag], 1) end
        local result = match and reconcileNode(match, child, ns, plan)
        if match then used[match] = true end
        if not result then
            result = build(child, ns, plan)
            if match then
                table.insert(plan.removals, match)
                if child.attrs.animation and match.attrs.animationValue ~= child.attrs.animationValue then
                    plan.animation = plan.animation or child.attrs.animation
                end
            end
        end
        results[index] = result
    end
    for _, child in ipairs(oldChildren) do
        if not used[child] then table.insert(plan.removals, child) end
    end
    local container = old.target
    for index, child in ipairs(results) do
        table.insert(plan.ops, function() ns._motionInsert(container, child.view, index) end)
    end
    return true
end

-- Reconciles `old` with `new`; returns the node to keep (the old views,
-- patched, carried by `new`) or nil when `new` must be built. `record`
-- nodes (columns, marks) must be identical.
reconcileNode = function(old, new, ns, plan, record)
    if old.tag ~= new.tag or identity(old) ~= identity(new) then return nil end
    if record then
        local same = true
        for key, value in pairs(old.attrs) do if new.attrs[key] ~= value then same = false end end
        for key, value in pairs(new.attrs) do if old.attrs[key] ~= value then same = false end end
        if not same then return nil end
        return reconcileChildren(old, new, ns, plan) and new or nil
    end
    if type(old.view) ~= "userdata" or old.tag == "LazyVStack" or old.tag == "LazyVGrid" then
        -- Lazy collections own their items; rebuild on any change.
        return nil
    end
    local ops, changed = attributePatch(old, new, ns)
    if not ops then return nil end
    local childPlan = { ops = {}, removals = {}, built = {}, animation = plan.animation }
    if not reconcileChildren(old, new, ns, childPlan) then
        for _, node in ipairs(childPlan.built) do disposeNode(node) end
        return nil
    end
    for _, op in ipairs(ops) do table.insert(plan.ops, op) end
    for _, op in ipairs(childPlan.ops) do table.insert(plan.ops, op) end
    for _, node in ipairs(childPlan.removals) do table.insert(plan.removals, node) end
    for _, node in ipairs(childPlan.built) do table.insert(plan.built, node) end
    plan.animation = plan.animation or childPlan.animation
    if not plan.animation and new.attrs.animation and changed.animationValue then
        plan.animation = new.attrs.animation
    end
    new.view, new.target, new.scope = old.view, old.target, old.scope
    return new
end

local function collectRefs(node, refs)
    if node.attrs.id and type(node.target) == "userdata" then refs[node.attrs.id] = node.target end
    for _, child in ipairs(elements(node.children)) do collectRefs(child, refs) end
end

local function findNode(node, id)
    if node.attrs.id == id then return node end
    for _, child in ipairs(elements(node.children)) do
        local found = findNode(child, id)
        if found then return found end
    end
end

-- A template that renders nothing or several siblings is hosted in a
-- stack, as xml.renderDescription hosts it.
local function rootNode(description)
    local nodes = expandComponents(parseXML(description.source), description)
    local roots = elements(nodes)
    if #roots == 1 then return roots[1] end
    return { kind = "element", tag = "VStack", attrs = {}, children = nodes }
end

--- Mounts a description into `host` for later reconciliation. Returns the
--- mounted tree, whose `view` and `refs` are current after each reconcile.
function M.mount(description, ns, host)
    ns = ns or require("ns")
    local root = rootNode(description)
    local previous, previousTracking = renderData, tracking
    renderData, tracking = description.data, true
    local ok, err = pcall(compile, { root }, ns, registry, {})
    renderData, tracking = previous, previousTracking
    if not ok then
        if root.scope then root.scope:dispose() end
        error(err)
    end
    if type(root.view) ~= "userdata" then error("Template mounts require a view root, not a Window") end
    local mounted = { root = root, view = root.view, refs = {} }
    collectRefs(root, mounted.refs)
    ns._motionInsert(host, root.view, 1)
    return mounted
end

--- Reconciles `mounted` with a new description. Changes apply inside the
--- current transaction, or inside the animation of a changed
--- `animationValue` when no transaction is open.
function M.reconcile(mounted, description, ns, host)
    ns = ns or require("ns")
    local root = rootNode(description)
    local plan = { ops = {}, removals = {}, built = {} }
    local previous, previousTracking = renderData, tracking
    renderData, tracking = description.data, true
    local ok, result = pcall(function()
        local kept = reconcileNode(mounted.root, root, ns, plan)
        if kept then return kept end
        build(root, ns, plan)
        table.insert(plan.removals, mounted.root)
        table.insert(plan.ops, function() ns._motionInsert(host, root.view, 1) end)
        return root
    end)
    renderData, tracking = previous, previousTracking
    if not ok then
        for _, node in ipairs(plan.built) do disposeNode(node) end
        error(result)
    end
    local function apply()
        for _, op in ipairs(plan.ops) do op() end
        for _, node in ipairs(plan.removals) do
            ns._motionRemove(node.view)
            disposeNode(node)
        end
    end
    local animation = require("ui.animation")
    if plan.animation and not animation.inTransaction() then
        ns.withAnimation(animation.Animation.parse(plan.animation), apply)
    else
        apply()
    end
    mounted.root, mounted.view = result, result.view
    for key in pairs(mounted.refs) do mounted.refs[key] = nil end
    collectRefs(result, mounted.refs)
    return mounted
end

--- Removes a mounted tree, playing its root's removal transition when a
--- transaction is animating, and disposes its callbacks.
function M.unmount(mounted, ns)
    ns = ns or require("ns")
    ns._motionRemove(mounted.root.view)
    disposeNode(mounted.root)
end

--- The Scope that owns the node with `id`, for mounting nested templates
--- that must be disposed when that node is rebuilt.
function M.scopeOf(mounted, id)
    local node = findNode(mounted.root, id)
    return node and node.scope
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

--- The contents of the file at `path`, or nil when there is none. Unlike a
--- template read, a missing file is an answer, not an error.
function M.source(path)
    local reader = nativeReadFile()
    if reader then
        local ok, body, err = pcall(reader, path)
        return ok and not err and body or nil
    end
    local file = io.open(path, "r")
    if not file then return nil end
    local body = file:read("*a")
    file:close()
    return body
end

-- Parses XML into plain element tables ({kind, tag, attrs, children}) for
-- callers that interpret a vocabulary of their own rather than native views.
function M.parse(src)
    src = src:gsub("^%s*<%?xml[^?]*%?>%s*", "")
             :gsub("^%s*<!DOCTYPE[^>]*>%s*", "")
    return parseXML(src, { trimText = true, decodeText = true })
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
