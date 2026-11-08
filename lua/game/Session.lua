-- A play session: which level is running, lives, score and the session's
-- state machine. The world runs the level; the session reacts to the
-- world's events and decides what they mean for the game.
--
--   playing ──cleared──▶ cleared ──advance──▶ playing (next level)
--      │                    └ last level ────▶ won ──advance──▶ playing (level 1)
--      └──out of lives───▶ over ─────advance──▶ playing (the same level, afresh)
--
-- A lost game costs the level, not the whole run: the level starts again
-- with full lives and the score it began with.
--
-- A game's session extends this one with its world, level parser, rules
-- and reactions:
--
--   local Model = require("game.Session"):extend({
--       World = World, parse = Level.parse, RULES = {lives = 3},
--       REACTIONS = {coin = function(self) self.score = self.score + 1 end},
--       QUIET = {sprung = true},
--   })
--
-- Every event a world emits needs a reaction; `hurt` and `cleared` have
-- the defaults below. An unknown event is an error, so a typo in a system
-- fails a test instead of being ignored.
--
-- `revision` counts changes the player can see beyond poses (a coin taken,
-- a life lost, a new state), so the controller renders the stage and HUD
-- templates only when it moves, not every frame. QUIET events change only
-- what poses already show.
local Session = {}
Session.__index = Session

Session.RULES = {lives = 3}
Session.QUIET = {}

Session.DEFAULT_REACTIONS = {
	hurt = function(self)
		self.lives = self.lives - 1
		if self.lives <= 0 then self.state = "over" else self.world:respawn() end
	end,
	cleared = function(self)
		self.state = self.levelIndex == #self.levels and "won" or "cleared"
	end,
}

function Session:extend(class)
	class = class or {}
	class.__index = class
	setmetatable(class, {__index = self})
	-- `Model.new(catalog, rules)` on every subclass.
	class.new = function(catalog, rules) return Session.create(class, catalog, rules) end
	return class
end

-- `catalog` is a list of level definitions, each parsed by the class's
-- `parse` into the level its World is built from.
function Session.create(class, catalog, rules)
	local self = setmetatable({rules = rules or class.RULES, levels = {}, revision = 0}, class)
	for _, def in ipairs(catalog) do table.insert(self.levels, class.parse(def)) end
	assert(#self.levels > 0, "a game needs at least one level")
	self:restart()
	return self
end

function Session:changed() self.revision = self.revision + 1 end

function Session:load(index)
	self.levelIndex = index
	self.levelScore, self.levelStars = self.score, self.stars
	self.world = self.World.new(self.levels[index])
	self.state = "playing"
	self:changed()
end

function Session:restart()
	self.lives, self.score, self.stars = self.rules.lives, 0, 0
	self:load(1)
end

-- Return, Space or a tap on a finished level or game.
function Session:advance()
	if self.state == "cleared" then
		self:load(self.levelIndex + 1)
	elseif self.state == "over" then
		self.lives, self.score, self.stars = self.rules.lives, self.levelScore, self.levelStars
		self:load(self.levelIndex)
	elseif self.state == "won" then
		self:restart()
	end
end

function Session:react(event)
	local reaction = (self.REACTIONS and self.REACTIONS[event.name]) or Session.DEFAULT_REACTIONS[event.name]
	if not reaction then error("no reaction to the world's event '" .. tostring(event.name) .. "'", 2) end
	reaction(self, event.entity)
end

-- Advances the running level by `dt` seconds with `input` (game.Input or
-- a scripted table). Nothing moves once the level ends.
function Session:step(dt, input)
	if self.state ~= "playing" then
		self.world:idle(dt)
		return
	end
	for _, event in ipairs(self.world:step(dt, input)) do
		self:react(event)
		if not self.QUIET[event.name] then self:changed() end
		if self.state ~= "playing" then return end
	end
end

function Session:level() return self.levels[self.levelIndex] end

function Session:poses() return self.world:poses() end

return Session
