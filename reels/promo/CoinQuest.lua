-- Coin Quest, replayed for the reel by the game itself: the real session
-- Model and World step at a fixed rate with a scripted game pad, and every
-- step's poses are recorded, so any instant of the playthrough can be drawn
-- exactly and motion-blur sub-frames interpolate between recorded steps.
-- The stage is the game's own Stage.etlua, fed by the game's own
-- StageController.viewData; the reel only adds the camera.
--
--   local quest = CoinQuest.new({level = 2, script = {{0.3, "left"}, …}, duration = 5})
--   quest:view()        -- data for apps/coin-quest/views/Stage.etlua
--   quest:poses(t)      -- `states` for the reel's <SceneView>
--   quest.events        -- {time, name} for the score: coins, the flag
local Model = require("apps.coin-quest.Model")
local Levels = require("apps.coin-quest.catalog.Levels")
local StageController = require("apps.coin-quest.controllers.StageController")

local CoinQuest = {}
CoinQuest.__index = CoinQuest

-- Steps per second of simulated time; the game itself runs at the display
-- rate, a hop lasts 0.16 s, so this resolves every hop smoothly.
local RATE = 240
-- The live SceneView's pop and rise transitions (kSceneTransition*).
local TRANSITION = { duration = 0.3, popScale = 1.6, rise = 1.0 }

local DIRECTIONS = { left = { x = -1, z = 0 }, right = { x = 1, z = 0 }, up = { x = 0, z = -1 }, down = { x = 0, z = 1 } }

-- options: level (index), script ({time, direction} presses in order),
-- duration (seconds simulated).
function CoinQuest.new(options)
	local self = setmetatable({ frames = {}, events = {}, taken = {}, duration = options.duration }, CoinQuest)
	local model = Model.new(Levels)
	model:load(options.level or 1)
	self.initial = model:scene()
	self.level = model:level()
	local presses, next = options.script or {}, 1
	local clock = 0
	local pad = {
		nextDirection = function()
			local press = presses[next]
			if press and clock >= press[1] then
				next = next + 1
				return DIRECTIONS[press[2]] or error("coin quest: unknown direction " .. tostring(press[2]))
			end
		end,
	}
	local dt = 1 / RATE
	for step = 0, math.ceil(options.duration * RATE) do
		clock = step * dt
		local events = model.world:step(dt, pad)
		for _, event in ipairs(events) do
			table.insert(self.events, { time = clock, name = event.name, id = event.entity and event.entity.id })
			if event.name == "coin" then self.taken[event.entity.id] = clock end
			if event.name == "flagRaised" then self.flagRaised = clock end
			if event.name == "hurt" then self.hurt = clock end
		end
		self.frames[step + 1] = model.world:poses()
	end
	return self
end

-- The Stage.etlua data: the level as it starts, with the flag present so
-- its node exists; poses keep it hidden until it rises.
function CoinQuest:view()
	local scene = {}
	for key, value in pairs(self.initial) do scene[key] = value end
	scene.flag = { x = self.initial.flag.x, z = self.initial.flag.z, raised = true }
	return StageController.viewData(scene)
end

local function lerp(a, b, p)
	if type(a) ~= "number" or type(b) ~= "number" then return a end
	return a + (b - a) * p
end

-- Poses at t: the recorded step's, interpolated with the next, then the
-- coins taken so far popping away and the flag rising once raised.
function CoinQuest:poses(t)
	local position = math.max(0, math.min(t, self.duration)) * RATE
	local index = math.floor(position)
	local p = position - index
	local a, b = self.frames[index + 1], self.frames[index + 2] or self.frames[index + 1]
	local poses = {}
	for i, pose in ipairs(a) do
		local other = b[i] or pose
		local blended = { id = pose.id }
		for key, value in pairs(pose) do
			if key ~= "id" then blended[key] = lerp(value, other[key], p) end
		end
		-- Yaw snaps when the player turns; interpolating across ±180 would spin.
		if pose.yaw then blended.yaw = pose.yaw end
		table.insert(poses, blended)
	end
	local d = TRANSITION.duration
	for id, at in pairs(self.taken) do
		local u = (t - at) / d
		if u >= 0 then
			table.insert(poses, u >= 1 and { id = id, hidden = true }
				or { id = id, scale = 1 + (TRANSITION.popScale - 1) * u, opacity = 1 - u })
		end
	end
	local flag = { id = "flag", hidden = true }
	if self.flagRaised and t >= self.flagRaised then
		local u = math.min(1, (t - self.flagRaised) / d)
		local e = 1 - (1 - u) * (1 - u)
		flag = { id = "flag", hidden = false, y = -TRANSITION.rise * (1 - e), opacity = e }
	end
	table.insert(poses, flag)
	return poses
end

-- Where the player is at t, for a camera that follows it.
function CoinQuest:player(t)
	for _, pose in ipairs(self:poses(t)) do
		if pose.id == "player" then return { pose.x, pose.y, pose.z } end
	end
end

return CoinQuest
