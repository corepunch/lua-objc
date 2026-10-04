-- Turns keys, touch gestures and game controllers into game intent: which
-- way to run and when to jump. The world asks `axis()` and `takeJump()`
-- every frame and cannot tell which of them is playing.
--
-- Directions are as seen from the camera: up runs away from it.
--
-- Keys: arrows or WASD run while held, several at once run diagonally;
-- Space jumps; Q and E turn the camera; Return continues after a level ends
-- and R restarts. Touch: a swipe runs that way until a swipe the other way
-- stops the hero; a tap jumps. A game controller (a real one, or the
-- on-screen one on a touch screen) runs with its stick or d-pad, jumps with
-- A or B and turns the camera with X and Y; after a level A or B continues.
local InputController = {}
InputController.__index = InputController

local DIRECTIONS = {
	left = {x = -1, z = 0}, a = {x = -1, z = 0},
	right = {x = 1, z = 0}, d = {x = 1, z = 0},
	up = {x = 0, z = -1}, w = {x = 0, z = -1},
	down = {x = 0, z = 1}, s = {x = 0, z = 1},
}
local COMMANDS = {["return"] = "advance", r = "restart"}
local TURNS = {q = -1, e = 1}

-- A stick tilted less than this is at rest.
local STICK = {deadZone = 0.15}

-- `commands` maps command names (advance, restart) to functions.
function InputController.new(commands)
	return setmetatable({commands = commands or {}, held = {}, heading = nil, jumpQueued = false,
		stickX = 0, stickZ = 0, pad = {}, turning = {}}, InputController)
end

-- The SceneView's `onKey`: returns whether the key is one the game uses.
function InputController:key(key, pressed)
	if DIRECTIONS[key] then
		self.held[key] = pressed or nil
		if pressed then self.heading = nil end
		return true
	end
	if TURNS[key] then
		self.turning[key] = pressed or nil
		return true
	end
	if key == "space" then
		if pressed then self.jumpQueued = true end
		return true
	end
	local command = COMMANDS[key]
	if not command then return false end
	if pressed and self.commands[command] then self.commands[command]() end
	return true
end

-- The SceneView's `onSwipe`: run that way, or stop if it is the way back.
function InputController:swipe(name)
	local direction = DIRECTIONS[name]
	if not direction then return end
	local heading = self.heading
	if heading and heading.x == -direction.x and heading.z == -direction.z then
		self.heading = nil
	else
		self.heading = direction
	end
end

-- A tap, or anything else that jumps.
function InputController:jump()
	self.jumpQueued = true
end

-- A game controller's state this frame (the SceneView's `gamepad`):
-- `{stickX, stickY, a, b, x, y}` with the stick's tilt (y up) and which face
-- buttons are down. A press of A or B jumps.
function InputController:gamepad(state)
	if not state then
		self.stickX, self.stickZ, self.pad = 0, 0, {}
		return
	end
	local x, y = state.stickX or 0, state.stickY or 0
	if x * x + y * y < STICK.deadZone * STICK.deadZone then x, y = 0, 0 end
	self.stickX, self.stickZ = x, -y
	if (state.a and not self.pad.a) or (state.b and not self.pad.b) then self.jumpQueued = true end
	self.pad = {a = state.a, b = state.b, x = state.x, y = state.y}
end

-- Which way to turn the camera round the hero: -1, 0 or 1.
function InputController:turn()
	local turn = 0
	for key in pairs(self.turning) do turn = turn + TURNS[key] end
	if self.pad.x then turn = turn - 1 end
	if self.pad.y then turn = turn + 1 end
	return math.max(-1, math.min(1, turn))
end

-- Which way to run: held keys, else the stick, else a swiped heading.
function InputController:axis()
	local x, z = 0, 0
	for key in pairs(self.held) do
		x, z = x + DIRECTIONS[key].x, z + DIRECTIONS[key].z
	end
	x, z = math.max(-1, math.min(1, x)), math.max(-1, math.min(1, z))
	if x ~= 0 or z ~= 0 then return x, z end
	if self.stickX ~= 0 or self.stickZ ~= 0 then return self.stickX, self.stickZ end
	if self.heading then return self.heading.x, self.heading.z end
	return 0, 0
end

-- Whether a jump was asked for since the last call.
function InputController:takeJump()
	local queued = self.jumpQueued
	self.jumpQueued = false
	return queued
end

-- Forgets a queued jump and any run, so a press on the "Level Complete"
-- screen does not carry into the next level. Held keys stay held.
function InputController:reset()
	self.jumpQueued, self.heading = false, nil
end

return InputController
