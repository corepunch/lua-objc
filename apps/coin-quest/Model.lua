-- Coin Quest's play session (game.Session): levels, lives, score and the
-- playing / cleared / over / won state machine come from the shared
-- session; this file says what Coin Quest's events mean and what the stage
-- and HUD show.
--
-- `revision` counts changes the player can see beyond poses, so the
-- controller renders the stage and HUD templates only when it moves.
local Level = require("apps.coin-quest.models.Level")
local World = require("apps.coin-quest.models.World")
local Session = require("game.Session")

-- What each of the world's events means; `hurt` and `cleared` are the
-- session's own (a life lost, the next level).
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
}

local Model = Session:extend({
	World = World,
	parse = Level.parse,
	RULES = {lives = 3},
	REACTIONS = REACTIONS,
	-- Events that only move things the poses already show: no template render.
	QUIET = {sprung = true, crumbled = true},
})

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
		levelStars = #world.stars - #World.left(world.stars),
		totalStars = #world.stars,
		score = self.score,
		lives = self.lives,
		maxLives = self.rules.lives,
		state = self.state,
		message = MESSAGES[self.state],
	}
end

-- The entities the stage draws: the level's blocks and props, and the
-- entities still in play. Taken coins are gone, so their nodes leave;
-- opened gates leave the same way.
function Model:scene()
	local world, level = self.world, self:level()
	local left = World.left
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

-- The camera: where it stands and the point it looks at.
function Model:camera() return {position = self.world.camera, focus = self.world.focus} end

return Model
