-- The play session (a game.Session): races in order, and the playing /
-- cleared / over / won states come from the shared session. This file says
-- what each of the world's events means, and what the stage and HUD show.
-- A race finished in the top three (`podium`) goes on to the next; a
-- lower place races the same track again.
local Level = require("demo.playground.models.Level")
local World = require("demo.playground.models.World")
local Countdown = require("demo.playground.models.systems.Countdown")
local Session = require("game.Session")

local Model = Session:extend({
	World = World,
	parse = Level.parse,
	RULES = {lives = 1, podium = 3},
	-- What each event means. Countdown, lap and place only change what
	-- the HUD shows.
	REACTIONS = {
		countdown = function() end,
		lap = function() end,
		place = function() end,
		finished = function(self, car)
			if car.place <= self.rules.podium then
				Session.DEFAULT_REACTIONS.cleared(self)
			else
				self.state = "over"
			end
		end,
	},
})

local function ordinal(n)
	local suffix = ({"st", "nd", "rd"})[n] or "th"
	return n .. suffix
end

-- The end-of-race message for the session's state.
function Model:message()
	local place = ordinal(self.world.player.place)
	if self.state == "cleared" then
		return {title = "You finished " .. place .. "!", detail = "Press Return or tap for the next race"}
	elseif self.state == "won" then
		return {title = "Champion!", detail = "You finished " .. place .. " in the last race. Press Return or tap to race again"}
	elseif self.state == "over" then
		return {title = "You finished " .. place, detail = string.format("Finish in the top %d to go on. Press Return or tap to race again", self.rules.podium)}
	end
	return nil
end

-- What the HUD shows.
function Model:status()
	local world, level = self.world, self:level()
	local car = world.player
	return {
		title = level.title,
		stage = string.format("Race %d of %d", self.levelIndex, #self.levels),
		lap = math.min(car.lap + 1, level.laps),
		laps = level.laps,
		place = car.place,
		cars = #world.rivals + 1,
		bestLap = car.bestLap,
		countdown = self.state == "playing" and Countdown.shown(world.clock) or nil,
		message = self:message(),
	}
end

-- What the stage draws.
function Model:scene()
	local world, level = self.world, self:level()
	return {id = level.id, pieces = level.pieces, player = world.player, rivals = world.rivals, view = self:camera()}
end

-- Where the camera stands and the point it looks at.
function Model:camera() return {position = self.world.camera, focus = self.world.focus} end

return Model
