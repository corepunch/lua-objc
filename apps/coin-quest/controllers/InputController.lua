-- Turns key presses into game intent. Arrow keys and WASD are directions;
-- Return/Space continue after a level ends and R restarts.
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
	return setmetatable({commands = commands or {}, held = {}, pending = nil}, InputController)
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

function InputController:nextDirection()
	local direction = self.pending
	self.pending = nil
	return direction or DIRECTIONS[self.held[#self.held]]
end

-- Forgets taps not yet read, so a key pressed on the "Level Complete"
-- screen does not move the player on the next level. Held keys stay held.
function InputController:reset()
	self.pending = nil
end

return InputController
