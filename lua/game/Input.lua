-- Turns keys, touch gestures and game controllers into game intent: a
-- direction (`axis()`), named buttons pressed (`take(name)`) or held
-- (`held(name)`), and a camera turn (`turn()`). A world asks these every
-- frame and cannot tell which device is playing, so tests and reels script
-- the same three questions with a plain table.
--
-- Directions are as seen from the camera: up runs away from it, `z` -1.
--
-- What each key and controller button means is data, `Input.BINDINGS`, which
-- a game replaces or extends (a shooter binds space to "fire"). A swipe
-- runs that way until a swipe the other way stops; a tap presses the
-- `tap` button. Command keys (Return, R) call the game's commands at once.
local Input = {}
Input.__index = Input

Input.BINDINGS = {
	directions = {
		left = {x = -1, z = 0}, a = {x = -1, z = 0},
		right = {x = 1, z = 0}, d = {x = 1, z = 0},
		up = {x = 0, z = -1}, w = {x = 0, z = -1},
		down = {x = 0, z = 1}, s = {x = 0, z = 1},
	},
	buttons = {space = "jump"}, -- key -> button
	pad = {a = "jump", b = "jump"}, -- controller face button -> button
	tap = "jump", -- what a tap on a touch screen presses
	turns = {q = -1, e = 1}, -- key -> camera turn
	padTurns = {x = -1, y = 1},
	commands = {["return"] = "advance", r = "restart"}, -- key -> command
}

-- A stick tilted less than this is at rest.
Input.STICK = {deadZone = 0.15}

-- `commands` maps command names (advance, restart) to functions;
-- `bindings` replaces Input.BINDINGS field by field.
function Input.new(commands, bindings)
	local merged = {}
	for k, v in pairs(Input.BINDINGS) do merged[k] = v end
	for k, v in pairs(bindings or {}) do merged[k] = v end
	return setmetatable({commands = commands or {}, bindings = merged, keys = {}, turning = {},
		pressed = {}, heading = nil, stickX = 0, stickZ = 0, pad = {}}, Input)
end

-- The SceneView's `onKey`: returns whether the key is one the game uses.
function Input:key(key, pressed)
	local b = self.bindings
	if b.directions[key] then
		self.keys[key] = pressed or nil
		if pressed then self.heading = nil end
		return true
	end
	if b.turns[key] then
		self.turning[key] = pressed or nil
		return true
	end
	local button = b.buttons[key]
	if button then
		self.keys[key] = pressed or nil
		if pressed then self.pressed[button] = true end
		return true
	end
	local command = b.commands[key]
	if not command then return false end
	if pressed and self.commands[command] then self.commands[command]() end
	return true
end

-- The SceneView's `onSwipe`: run that way, or stop if it is the way back.
function Input:swipe(name)
	local direction = self.bindings.directions[name]
	if not direction then return end
	local heading = self.heading
	if heading and heading.x == -direction.x and heading.z == -direction.z then
		self.heading = nil
	else
		self.heading = direction
	end
end

-- Presses a button from code: a tap, or a touch control.
function Input:press(button)
	self.pressed[button or self.bindings.tap] = true
end

-- A game controller's state this frame (the SceneView's `gamepad`):
-- `{stickX, stickY, a, b, x, y}` with the stick's tilt (y up) and which face
-- buttons are down. A button counts as pressed on the frame it goes down.
function Input:gamepad(state)
	if not state then
		self.stickX, self.stickZ, self.pad = 0, 0, {}
		return
	end
	local x, y = state.stickX or 0, state.stickY or 0
	if x * x + y * y < Input.STICK.deadZone * Input.STICK.deadZone then x, y = 0, 0 end
	self.stickX, self.stickZ = x, -y
	for face, button in pairs(self.bindings.pad) do
		if state[face] and not self.pad[face] then self.pressed[button] = true end
	end
	self.pad = {a = state.a, b = state.b, x = state.x, y = state.y}
end

-- Which way to turn the camera: -1, 0 or 1.
function Input:turn()
	local turn = 0
	for key in pairs(self.turning) do turn = turn + self.bindings.turns[key] end
	for face, direction in pairs(self.bindings.padTurns) do
		if self.pad[face] then turn = turn + direction end
	end
	return math.max(-1, math.min(1, turn))
end

-- Which way to go: held keys, else the stick, else a swiped heading.
function Input:axis()
	local x, z = 0, 0
	for key in pairs(self.keys) do
		local d = self.bindings.directions[key]
		if d then x, z = x + d.x, z + d.z end
	end
	x, z = math.max(-1, math.min(1, x)), math.max(-1, math.min(1, z))
	if x ~= 0 or z ~= 0 then return x, z end
	if self.stickX ~= 0 or self.stickZ ~= 0 then return self.stickX, self.stickZ end
	if self.heading then return self.heading.x, self.heading.z end
	return 0, 0
end

-- Whether `button` was pressed since the last call: a jump, a shot.
function Input:take(button)
	local pressed = self.pressed[button]
	self.pressed[button] = nil
	return pressed == true
end

-- Whether `button` is down now, for things that repeat while held.
function Input:held(button)
	for key in pairs(self.keys) do
		if self.bindings.buttons[key] == button then return true end
	end
	for face, bound in pairs(self.bindings.pad) do
		if bound == button and self.pad[face] then return true end
	end
	return false
end

-- Forgets presses and a swiped run, so a press on the "Level Complete"
-- screen does not carry into the next level. Held keys stay held.
function Input:reset()
	self.pressed, self.heading = {}, nil
end

return Input
