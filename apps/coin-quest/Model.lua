-- A play session: which level is running, lives, score and the session's
-- state machine. The World runs the level; the session reacts to the
-- world's events and decides what they mean for the game.
--
--   playing ──cleared──▶ cleared ──advance──▶ playing (next level)
--      │                    └ last level ────▶ won ──advance──▶ playing (level 1)
--      └──out of lives───▶ over ─────advance──▶ playing (the same level, afresh)
--
-- A lost game costs the level, not the whole run: the level starts again
-- with full lives and the score it began with.
--
-- `revision` counts changes the player can see beyond poses (a coin taken,
-- the flag raised, a life lost, a new state), so the controller renders the
-- stage and HUD templates only when it moves, not every frame.
local Level = require("apps.coin-quest.models.Level")
local World = require("apps.coin-quest.models.World")

local Model = {}
Model.__index = Model

Model.RULES = {lives = 3}

-- `catalog` is a list of level definitions (catalog/Levels.lua).
function Model.new(catalog, rules)
	local self = setmetatable({rules = rules or Model.RULES, levels = {}, revision = 0}, Model)
	for _, def in ipairs(catalog) do table.insert(self.levels, Level.parse(def)) end
	assert(#self.levels > 0, "Coin Quest needs at least one level")
	self:restart()
	return self
end

function Model:changed() self.revision = self.revision + 1 end

function Model:load(index)
	self.levelIndex = index
	self.levelScore, self.levelStars = self.score, self.stars
	self.world = World.new(self.levels[index])
	self.state = "playing"
	self:changed()
end

function Model:restart()
	self.lives, self.score, self.stars = self.rules.lives, 0, 0
	self:load(1)
end

-- Return/Space on a finished level or game.
function Model:advance()
	if self.state == "cleared" then
		self:load(self.levelIndex + 1)
	elseif self.state == "over" then
		self.lives, self.score, self.stars = self.rules.lives, self.levelScore, self.levelStars
		self:load(self.levelIndex)
	elseif self.state == "won" then
		self:restart()
	end
end

local REACTIONS = {
	coin = function(self) self.score = self.score + 1 end,
	star = function(self) self.stars = self.stars + 1 end,
	flagRaised = function() end,
	key = function() end,
	unlocked = function() end,
	crumbled = function() end,
	sprung = function() end,
	checkpoint = function() end,
	heart = function(self) self.lives = math.min(self.rules.lives, self.lives + 1) end,
	hurt = function(self)
		self.lives = self.lives - 1
		if self.lives <= 0 then self.state = "over" else self.world:respawn() end
	end,
	cleared = function(self)
		self.state = self.levelIndex == #self.levels and "won" or "cleared"
	end,
}

-- Events that only move things the poses already show: no template render.
local QUIET = {sprung = true, crumbled = true}

-- Advances the running level by `dt` seconds. `input` answers `axis()` with
-- the direction to run and `takeJump()`. Nothing moves once the level ends.
function Model:step(dt, input)
	if self.state ~= "playing" then
		self.world:idle(dt)
		return
	end
	for _, event in ipairs(self.world:step(dt, input)) do
		REACTIONS[event.name](self, event.entity)
		if not QUIET[event.name] then self:changed() end
		if self.state ~= "playing" then return end
	end
end

function Model:level() return self.levels[self.levelIndex] end

-- What the HUD shows.
local MESSAGES = {
	cleared = {title = "Level Complete", detail = "Press Return or tap for the next level"},
	over = {title = "Out of Lives", detail = "Press Return or tap to try this level again"},
	won = {title = "You Win!", detail = "Every coin collected. Press Return or tap to play again"},
}

function Model:status()
	local world = self.world
	return {
		level = self:level().title,
		stage = string.format("Level %d of %d", self.levelIndex, #self.levels),
		coins = #world.coins - world:coinsLeft(),
		totalCoins = #world.coins,
		levelStars = #world.stars - #self:leftOf(world.stars),
		totalStars = #world.stars,
		score = self.score,
		lives = self.lives,
		maxLives = self.rules.lives,
		state = self.state,
		message = MESSAGES[self.state],
	}
end

-- The items of a list not yet taken.
function Model:leftOf(list)
	local out = {}
	for _, item in ipairs(list) do if not item.taken then table.insert(out, item) end end
	return out
end

-- The entities the stage draws: the level's blocks and props, and the
-- entities still in play. Taken coins are gone, so their nodes leave;
-- opened gates leave the same way.
function Model:scene()
	local world, level = self.world, self:level()
	local function left(list) return self:leftOf(list) end
	local gates = {}
	for _, gate in ipairs(world.gates) do if not gate.open then table.insert(gates, gate) end end
	return {
		id = level.id,
		biome = level.biome,
		blocks = level.blocks,
		props = level.props,
		start = level.spawns.player,
		view = {position = world.camera, focus = world.focus},
		coins = left(world.coins),
		stars = left(world.stars),
		hearts = left(world.hearts),
		keys = left(world.keys),
		checkpoints = world.checkpoints,
		springs = world.springs,
		gates = gates,
		movers = world.movers,
		planks = world.planks,
		saws = world.saws,
		spikes = world.spikes,
		flag = world.flag,
	}
end

function Model:poses() return self.world:poses() end

-- The camera: where it stands and the point it looks at.
function Model:camera() return {position = self.world.camera, focus = self.world.focus} end

return Model
