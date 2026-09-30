-- Turns key presses and touch gestures into game intent. Arrow keys and WASD
-- are directions; Return/Space continue after a level ends and R restarts.
--
-- On a touch screen a swipe sets a heading and the player keeps running
-- that way, hop after hop, until a tap stops it or the way is blocked (a
-- swipe the other way turns it round). Keys and swipes feed the same
-- `nextDirection`, so the world cannot tell which one is playing.
--
-- The world reads one direction whenever the player is ready to hop
-- (`nextDirection`). A tap shorter than a frame still counts: a press is
-- remembered until it is read. Holding keeps hopping, and the most
-- recently pressed of several held directions wins, like a game pad.
local InputController = {}
InputController.__index = InputController

local DIRECTIONS = {
	left = {x = -1, z = 0}, a = {x = -1, z = 0},
	right = {x = 1, z = 0}, d = {x = 1, z = 0},
	up = {x = 0, z = -1}, w = {x = 0, z = -1},
	down = {x = 0, z = 1}, s = {x = 0, z = 1},
}
local COMMANDS = {["return"] = "advance", space = "advance", r = "restart"}

-- `commands` maps command names (advance, restart) to functions.
function InputController.new(commands)
	return setmetatable({commands = commands or {}, held = {}, pending = nil, heading = nil}, InputController)
end

local function release(held, key)
	for index = #held, 1, -1 do
		if held[index] == key then table.remove(held, index) end
	end
end

-- The SceneView's `onKey`: returns whether the key is one the game uses.
function InputController:key(key, pressed)
	if DIRECTIONS[key] then
		release(self.held, key)
		if pressed then
			table.insert(self.held, key)
			self.pending = DIRECTIONS[key]
		end
		return true
	end
	local command = COMMANDS[key]
	if not command then return false end
	if pressed and self.commands[command] then self.commands[command]() end
	return true
end

-- The SceneView's `onSwipe`: run that way until stopped.
function InputController:swipe(name)
	local direction = DIRECTIONS[name]
	if not direction then return end
	self.heading, self.pending = direction, direction
end

-- Stops a running player. Reports whether there was a run to stop, so the
-- controller can use the same tap to continue after a level ends.
function InputController:stop()
	local running = self.heading ~= nil
	self.heading, self.pending = nil, nil
	return running
end

-- The world reports a blocked way (an island's edge, a crate): the run ends
-- there instead of pushing on the spot forever.
function InputController:blocked(direction)
	if self.heading == direction then self.heading = nil end
end

function InputController:nextDirection()
	local direction = self.pending
	self.pending = nil
	return direction or DIRECTIONS[self.held[#self.held]] or self.heading
end

-- Forgets taps not yet read and any run, so a key pressed on the "Level
-- Complete" screen does not move the player on the next level. Held keys
-- stay held.
function InputController:reset()
	self.pending, self.heading = nil, nil
end

return InputController
