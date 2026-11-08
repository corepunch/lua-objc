-- The play session (a game.Session): levels, lives, score and the playing /
-- cleared / over / won states come from the shared session. This file says
-- what each of the world's events means, and what the stage and HUD show.
local Level = require("demo.playground.models.Level")
local World = require("demo.playground.models.World")
local Session = require("game.Session")

local Model = Session:extend({
	World = World,
	parse = Level.parse,
	RULES = {lives = 3},
	-- What each event means; `hurt` and `cleared` are the session's own
	-- (a life lost, the next level).
	REACTIONS = {
		coin = function(self) self.score = self.score + 1 end,
		flagRaised = function() end,
		sprung = function() end,
		animation = function() end,
	},
	-- Events that only move what the poses already show: no template render.
	QUIET = {sprung = true},
})

local MESSAGES = {
	cleared = {title = "Level Complete", detail = "Press Return or tap for the next level"},
	over = {title = "Out of Lives", detail = "Press Return or tap to try again"},
	won = {title = "You Win!", detail = "Press Return or tap to play again"},
}

-- What the HUD shows.
function Model:status()
	local world = self.world
	return {
		title = self:level().title,
		stage = string.format("Level %d of %d", self.levelIndex, #self.levels),
		coins = #world.coins - #World.left(world.coins),
		totalCoins = #world.coins,
		lives = self.lives,
		maxLives = self.rules.lives,
		message = MESSAGES[self.state],
	}
end

-- What the stage draws. Taken coins are gone, so their nodes leave.
function Model:scene()
	local world, level = self.world, self:level()
	return {
		id = level.id,
		biome = level.biome,
		pieces = level.pieces,
		start = level.start,
		player = world.player,
		view = self:camera(),
		coins = World.left(world.coins),
		springs = world.springs,
		spikes = world.spikes,
		flag = world.flag,
	}
end

-- Where the camera stands and the point it looks at.
function Model:camera() return {position = self.world.camera, focus = self.world.focus} end

return Model
