-- Lua components: new XML tags written in Lua and composed from the native
-- views every platform already has (stacks, Arc, Label, SystemImage...), the
-- way `SectorChart` composes native arcs. A component is a module returning
-- a definition:
--
--   return {
--   	props = { lineWidth = "num", tint = { type = "str", default = "accent" } },
--   	records = { ActivityRing = { value = "num", goal = "num", color = "str" } },
--   	actions = { "onSelect" },
--   	build = function(self, ns) ... return view end,
--   	update = function(self, ns) ... end,          -- optional
--   	accepts = function(self, props, records) ... end, -- optional
--   }
--
-- `self.props` holds the declared attributes (typed as in the XML schema,
-- with defaults), `self.records` the record children in order,
-- `self.content` the view children, `self.actions` the bound callbacks and
-- `self.layout` the frame attributes (width, maxWidth, padding, background)
-- for the root view; `Component.frame(self, defaults)` merges them. Every
-- component also takes `accessibilityLabel`, applied to its root.
--
-- `update` makes the component retained: a template reconcile hands it new
-- `self.props` and `self.records` and it moves its existing views, inside the
-- current animation transaction, instead of being rebuilt. `accepts` may
-- decline a change it cannot apply in place (a different number of cells);
-- the reconciler then rebuilds the node. Without `update` every change
-- rebuilds.
--
-- Resolution: a tag outside the vocabulary is looked up in the `components/`
-- folder nearest the rendering template (an app's `components/` beside its
-- `views/`), then in the framework's bundled `lua/components/`. The module
-- file is named after the tag. Geometry belongs in plain functions on the
-- module so tests can check it without building views.
local Component = {}

local instances = setmetatable({}, { __mode = "k" })
-- tag -> module name that defined it, so two components cannot share a tag,
-- and the definition registered for it, so a reloaded module re-registers.
local owners, definitions = {}, {}

local function copy(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end

-- Root frame attributes: the component's defaults, overridden by the frame
-- the template gave it. Integer entries of `defaults` are children.
function Component.frame(self, defaults)
	local result = copy(defaults)
	for key, value in pairs(self.layout) do result[key] = value end
	return result
end

-- The instance state of a view a component built, for tests and callbacks.
function Component.instance(view)
	return instances[view]
end

local function split(def, props)
	local self = { props = {}, layout = {}, records = {}, content = {}, actions = {} }
	local actions = {}
	for _, name in ipairs(def.actions or {}) do actions[name] = true end
	for key, value in pairs(props) do
		if type(key) == "number" then
			if type(value) == "table" and value.__record then
				-- placed below, in document order
			else
				table.insert(self.content, value)
			end
		elseif actions[key] then
			self.actions[key] = value
		elseif def.props[key] ~= nil then
			self.props[key] = value
		else
			self.layout[key] = value
		end
	end
	for _, value in ipairs(props) do
		if type(value) == "table" and value.__record then table.insert(self.records, value) end
	end
	return self
end

local function recordsOf(list)
	local records = {}
	for _, value in ipairs(list) do
		if type(value) == "table" and value.__record then table.insert(records, value) end
	end
	return records
end

--- Registers component `def` as XML tag `tag`, and its record tags.
--- `source` names the module, so reloading it replaces the definition while
--- a second module claiming the same tag is an error.
function Component.define(tag, def, source)
	assert(type(def) == "table" and type(def.build) == "function",
		"component <" .. tostring(tag) .. "> needs a build(self, ns) function")
	source = source or tag
	for name in pairs(def.records or {}) do
		if owners[name] and owners[name] ~= source then
			error("component: <" .. name .. "> is already defined by " .. owners[name])
		end
	end
	if owners[tag] and owners[tag] ~= source then
		error("component: <" .. tag .. "> is already defined by " .. owners[tag])
	end
	local xml = require("ui.xml")
	def.props = copy(def.props)
	if def.props.accessibilityLabel == nil then def.props.accessibilityLabel = "str" end
	for name, props in pairs(def.records or {}) do
		xml.define(name, {
			kind = "record", props = props,
			transform = function(record) record.__record = name end,
		})
		owners[name] = source
	end
	xml.define(tag, {
		component = true, children = "array", props = def.props, actions = def.actions,
		build = function(ns, props)
			local self = split(def, props)
			self.ns, self.tag = ns, tag
			local view = def.build(self, ns)
			assert(type(view) == "userdata", "component <" .. tag .. "> build must return one native view")
			if self.props.accessibilityLabel then view.accessibilityLabel = self.props.accessibilityLabel end
			self.view = view
			instances[view] = self
			return view
		end,
		patch = def.update and function(view, props, records)
			local self = instances[view]
			if not self then return nil end
			local nextRecords = records and recordsOf(records) or self.records
			if def.accepts and not def.accepts(self, props, nextRecords) then return nil end
			return function()
				self.props, self.records = props, nextRecords
				def.update(self, self.ns)
				view.accessibilityLabel = props.accessibilityLabel or ""
			end
		end or nil,
	})
	owners[tag], definitions[tag] = source, def
	return def
end

-- Loads module `name` if it exists; errors inside an existing module propagate.
local function load(name)
	local ok, result = pcall(require, name)
	if ok then return result end
	if tostring(result):find("module '" .. name .. "' not found", 1, true) then return nil end
	error(result, 0)
end

-- Directories from `baseDir` up to the working directory, nearest first.
local function ancestors(baseDir)
	local dirs = {}
	local parts = {}
	-- Modules resolve against the working directory; an absolute template
	-- path has no module name.
	if tostring(baseDir or ""):match("^/") then return dirs end
	for part in tostring(baseDir or ""):gsub("\\", "/"):gmatch("[^/]+") do
		if part ~= "." then table.insert(parts, part) end
	end
	for count = #parts, 1, -1 do
		table.insert(dirs, table.concat(parts, ".", 1, count))
	end
	return dirs
end

--- The XML handler for component `tag` near `baseDir`, or nil. App
--- components shadow bundled ones of the same name.
function Component.resolve(tag, baseDir)
	if type(tag) ~= "string" or not tag:match("^%u[%w]*$") then return nil end
	local xml = require("ui.xml")
	local candidates = {}
	-- A defined tag stays with its module; only a reload changes it.
	if owners[tag] then table.insert(candidates, owners[tag]) end
	for _, dir in ipairs(ancestors(baseDir)) do
		if not dir:find("%.%.") and dir:match("^[%w_.-]+$") then
			table.insert(candidates, dir .. ".components." .. tag)
		end
	end
	table.insert(candidates, "components." .. tag)
	for _, name in ipairs(candidates) do
		local def = load(name)
		if def ~= nil then
			assert(type(def) == "table", "component module " .. name .. " must return a definition table")
			if definitions[tag] ~= def then Component.define(tag, def, name) end
			return xml.registry[tag]
		end
	end
	return nil
end

return Component
