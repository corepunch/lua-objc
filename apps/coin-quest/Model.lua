-- A play session: which level is running, lives, score and the session's
-- state machine. The World runs the level; the session reacts to the
-- world's events and decides what they mean for the game.
--
--   playing ──cleared──▶ cleared ──advance──▶ playing (next level)
--      │                    └ last level ────▶ won ──advance──▶ playing (level 1)
--      └──out of lives───▶ over ─────advance──▶ playing (level 1)
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
	self.world = World.new(self.levels[index])
	self.state = "playing"
	self:changed()
end

function Model:restart()
	self.lives, self.score = self.rules.lives, 0
	self:load(1)
end

-- Return/Space on a finished level or game.
function Model:advance()
	if self.state == "cleared" then
		self:load(self.levelIndex + 1)
	elseif self.state == "over" or self.state == "won" then
		self:restart()
	end
end

local REACTIONS = {
	coin = function(self) self.score = self.score + 1 end,
	flagRaised = function() end,
	hurt = function(self)
		self.lives = self.lives - 1
		if self.lives <= 0 then self.state = "over" else self.world:respawn() end
	end,
	cleared = function(self)
		self.state = self.levelIndex == #self.levels and "won" or "cleared"
	end,
}

-- Advances the running level by `dt` seconds. `input` answers
-- `nextDirection()` with `{x, z}` or nil. Nothing moves once the level ends.
function Model:step(dt, input)
	if self.state ~= "playing" then return end
	for _, event in ipairs(self.world:step(dt, input)) do
		REACTIONS[event.name](self, event.entity)
		self:changed()
		if self.state ~= "playing" then return end
	end
end

function Model:level() return self.levels[self.levelIndex] end

-- What the HUD shows.
local MESSAGES = {
	cleared = {title = "Level Complete", detail = "Press Return for the next level"},
	over = {title = "Game Over", detail = "Press Return to play again"},
	won = {title = "You Win!", detail = "Every coin collected. Press Return to play again"},
}

function Model:status()
	local world = self.world
	return {
		level = self:level().title,
		stage = string.format("Level %d of %d", self.levelIndex, #self.levels),
		coins = #world.coins - world:coinsLeft(),
		totalCoins = #world.coins,
		score = self.score,
		lives = self.lives,
		maxLives = self.rules.lives,
		state = self.state,
		message = MESSAGES[self.state],
	}
end

-- The entities the stage draws: the level's ground and scenery, and the
-- entities still in play. Taken coins are gone, so their nodes leave.
function Model:scene()
	local world, level = self.world, self:level()
	local coins = {}
	for _, coin in ipairs(world.coins) do if not coin.taken then table.insert(coins, coin) end end
	return {
		id = level.id,
		width = level.width,
		depth = level.depth,
		tiles = level.tiles,
		scenery = level.scenery,
		start = level.spawns.player,
		coins = coins,
		saws = world.saws,
		spikes = world.spikes,
		flag = world.flag,
	}
end

function Model:poses() return self.world:poses() end

return Model
