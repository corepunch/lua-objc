-- Models and the dependency graph.
--
-- A model is plain Lua data that computes: it owns queries, validation and
-- mutation and never touches `ns`. A computed presentation (Clean Up reads
-- the scan, the applications inventory, the simulator plan and Keep) is a
-- model too, and declares what it needs in its own file, not in the manifest:
--
--   local Recommendations = Model.define({
--   	id = "cleanup",
--   	needs = {"scan", "applications", "simulatorPlan", "keep"},
--   })
--   function Recommendations.new(needs, services) ... end
--   return Recommendations
--
-- `new` receives the already built instances it needs, by id, and the
-- services the graph was given. The graph is the bootstrap: showing one page
-- builds its model and the models that one needs, transitively, in
-- dependency order, and nothing else. A cycle is an error naming its path.
--
-- There are no notifications. A page is rendered from its model's data when
-- it is shown, and again when the app says its data changed (a finished scan,
-- an action): ask the model again, render again, like a request.
local Model = {}

function Model.define(spec)
	assert(type(spec) == "table", "Model.define needs a table")
	if type(spec.id) ~= "string" or spec.id == "" then error("Model.define needs an id", 2) end
	local needs = spec.needs or {}
	for _, need in ipairs(needs) do
		if type(need) ~= "string" then error("model " .. spec.id .. ": needs lists model ids", 2) end
	end
	local class = { id = spec.id, needs = needs }
	class.__index = class
	return class
end

local Graph = {}
Graph.__index = Graph

-- `options.classes`: id -> class made by Model.define (or a function taking
-- an id and returning one). `options.services` is handed to every `new`.
function Model.graph(options)
	options = options or {}
	return setmetatable({
		classes = options.classes or {},
		services = options.services or {},
		instances = {},
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
			self.instances[id] = instance
		end
	end
	local built = {}
	for _, id in ipairs(ids) do built[id] = self.instances[id] end
	return built
end

function Graph:get(id)
	return self.instances[id]
end

return Model
