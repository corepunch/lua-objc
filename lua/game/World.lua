-- The running state of one level: entities, a clock, and the events of the
-- current step. A game's world extends this one:
--
--   local World = require("game.World"):extend({
--       RULES = {runSpeed = 5, gravity = 26},
--       SYSTEMS = {(require("mygame.models.systems.Hero")), ...},
--   })
--   function World.new(level, rules)
--       local self = World.create(level, rules)
--       self.coins = World.spawnAll(level.spawns.coins, "coin")
--       return self
--   end
--
-- Entities are plain tables grouped by kind. Behaviour lives in systems,
-- each a module with `update(world, dt, input)` holding one rule and run in
-- the class's SYSTEMS order every step, so a rule is a small file that is
-- tested alone with a hand-built world. Systems never call the session:
-- they `emit` events ("coin", "hurt", "cleared") and the session decides
-- what each means. Nothing here knows AppKit, UIKit or a scene node.
local World = {}
World.__index = World
World.RULES = {}
World.SYSTEMS = {}

-- A subclass: `class` holds its RULES, SYSTEMS and methods.
function World:extend(class)
	class = class or {}
	class.__index = class
	return setmetatable(class, {__index = self})
end

-- An instance of the class it is called on, before any entity spawns.
function World.create(level, rules, class)
	return setmetatable({level = level, rules = rules or class.RULES, time = 0, events = {}}, class)
end

-- Entities from a level's spawn list, with ids "<prefix>-<n>" that the
-- stage template gives their nodes. `extra(entity)` adds per-kind state.
function World.spawnAll(list, prefix, extra)
	local entities = {}
	for index, spawn in ipairs(list or {}) do
		local entity = {id = prefix .. "-" .. index}
		for k, v in pairs(spawn) do entity[k] = v end
		if extra then extra(entity) end
		table.insert(entities, entity)
	end
	return entities
end

function World:emit(name, entity)
	table.insert(self.events, {name = name, entity = entity})
end

-- Advances every system by `dt` seconds and returns the events raised.
function World:step(dt, input)
	self.events = {}
	self.time = self.time + dt
	for _, system in ipairs(self.SYSTEMS) do system.update(self, dt, input) end
	return self.events
end

-- Time passes on a finished level, so a hero can celebrate; nothing moves.
function World:idle(dt)
	self.time = self.time + dt
end

-- The items of a list not yet taken.
function World.left(list)
	local out = {}
	for _, item in ipairs(list) do if not item.taken then table.insert(out, item) end end
	return out
end

return World
