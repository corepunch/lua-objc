-- Models and the dependency graph.
--
-- A model is plain Lua data that computes: it owns queries, validation and
-- mutation and never touches `ns`. A computed presentation (Clean Up reads
-- the scan, the applications inventory, the simulator plan and Keep) is a
-- model too, and declares what it needs in its own file, not in the manifest:
--
--   local Recommendations = Model.define({
--   	id = "cleanup",
--   	schema = "Recommendations",
--   	needs = {"scan", "applications", "simulatorPlan", "keep"},
--   })
--   function Recommendations.new(needs, services) ... end
--   return Recommendations
--
-- `new` receives the already built instances it needs, by id, and the
-- services the graph was given. The graph is the bootstrap: launching one
-- page builds its model's dependencies transitively, in dependency order,
-- and nothing else. A cycle is an error at startup.
--
-- Propagation stays explicit: models are not observed. `graph:changed(id)`
-- says one changed; the graph walks its dependents, calls `invalidate` on
-- each built one (a computed model drops what it cached) and notifies the
-- subscribers of every stale model, which rebind the views bound to them.
-- That is WPF's PropertyChanged with an empty property name: rebind
-- everything on this context, not one property.
local Events = require("data.events")
local Model = {}

function Model.define(spec)
	assert(type(spec) == "table", "Model.define needs a table")
	if type(spec.id) ~= "string" or spec.id == "" then error("Model.define needs an id", 2) end
	local needs = spec.needs or {}
	for _, need in ipairs(needs) do
		if type(need) ~= "string" then error("model " .. spec.id .. ": needs lists model ids", 2) end
	end
	local class = { id = spec.id, schema = spec.schema, needs = needs }
	class.__index = class
	return class
end

local Graph = {}
Graph.__index = Graph

-- `options.classes`: id -> class made by Model.define (or a function taking
-- an id and returning one). `options.services` is handed to every `new`.
-- `options.schemas` is a schema loader: a built model is checked against its
-- schema and fails to build when it lacks a declared field.
function Model.graph(options)
	options = options or {}
	return setmetatable({
		classes = options.classes or {},
		services = options.services or {},
		schemas = options.schemas,
		instances = {},
		order = {},
		subscribers = {},
	}, Graph)
end

function Graph:class(id)
	local class = self.classes[id]
	if type(class) == "function" then class = class(id); self.classes[id] = class end
	if not class then error("model graph: no model \"" .. id .. "\" is registered", 0) end
	if class.id ~= id then
		error("model graph: \"" .. id .. "\" is registered as a class whose id is \"" .. tostring(class.id) .. "\"", 0)
	end
	return class
end

-- The ids to build for `ids`, dependencies first.
function Graph:plan(ids)
	local planned, state, trail = {}, {}, {}
	local function visit(id)
		if state[id] == "done" then return end
		if state[id] == "visiting" then
			local cycle = {}
			local started
			for _, member in ipairs(trail) do
				if member == id then started = true end
				if started then table.insert(cycle, member) end
			end
			table.insert(cycle, id)
			error("model graph: dependency cycle " .. table.concat(cycle, " -> "), 0)
		end
		state[id] = "visiting"
		table.insert(trail, id)
		for _, need in ipairs(self:class(id).needs) do visit(need) end
		table.remove(trail)
		state[id] = "done"
		table.insert(planned, id)
	end
	for _, id in ipairs(ids) do visit(id) end
	return planned
end

-- Builds the models `ids` need (each once) and returns them by id.
function Graph:build(ids)
	for _, id in ipairs(self:plan(ids)) do
		if not self.instances[id] then
			local class = self:class(id)
			local needs = {}
			for _, need in ipairs(class.needs) do needs[need] = self.instances[need] end
			local instance = class.new(needs, self.services)
			if type(instance) ~= "table" then error("model " .. id .. ": new must return the model", 0) end
			if class.schema and self.schemas then
				self.schemas(class.schema):check(instance)
			end
			self.instances[id] = instance
			table.insert(self.order, id)
			-- `model:changed()` says this model changed, from anywhere: a
			-- service callback, a timer, a command. The rebind is an event.
			rawset(instance, "changed", function() self:post(id) end)
		end
	end
	local built = {}
	for _, id in ipairs(ids) do built[id] = self.instances[id] end
	return built
end

function Graph:get(id)
	return self.instances[id]
end

-- Registered models that need `id` directly.
function Graph:dependents(id)
	local found = {}
	for candidate, class in pairs(self.classes) do
		if type(class) == "table" then
			for _, need in ipairs(class.needs) do
				if need == id then table.insert(found, candidate) end
			end
		end
	end
	table.sort(found)
	return found
end

-- Calls `callback(stale)` after each change, for the stale ids it names.
-- Returns a function that cancels the subscription.
function Graph:subscribe(id, callback)
	self.subscribers[id] = self.subscribers[id] or {}
	table.insert(self.subscribers[id], callback)
	return function()
		for index, candidate in ipairs(self.subscribers[id]) do
			if candidate == callback then table.remove(self.subscribers[id], index); return end
		end
	end
end

-- Posts the change of `id` as an event; bursts coalesce into one `changed`.
function Graph:post(id)
	self.dirty = self.dirty or {}
	table.insert(self.dirty, id)
	Events.post(function()
		local ids, seen = self.dirty, {}
		self.dirty = nil
		for _, dirtyId in ipairs(ids or {}) do
			if not seen[dirtyId] then seen[dirtyId] = true; self:changed(dirtyId) end
		end
	end, self)
end

-- Marks `id` and everything built that depends on it, transitively, stale.
-- Returns the stale ids in dependency order.
function Graph:changed(id)
	self:class(id)
	local stale, seen = {}, {}
	local function visit(model)
		if seen[model] then return end
		seen[model] = true
		for _, dependent in ipairs(self:dependents(model)) do visit(dependent) end
	end
	visit(id)
	for _, built in ipairs(self.order) do
		if seen[built] then table.insert(stale, built) end
	end
	for _, staleId in ipairs(stale) do
		local instance = self.instances[staleId]
		if staleId ~= id and type(instance.invalidate) == "function" then instance:invalidate(id) end
	end
	for _, staleId in ipairs(stale) do
		for _, callback in ipairs(self.subscribers[staleId] or {}) do callback(stale) end
	end
	return stale
end

return Model
