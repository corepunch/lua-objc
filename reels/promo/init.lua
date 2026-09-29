-- The lua-objc promo: a 30-second film rendered with the Reel module.
--
--   ./lua-objc reels/promo/init.lua stills <out dir> <t1,t2,…>
--   ./lua-objc reels/promo/init.lua render <out.mov> [from to]
--
-- views/Reel.etlua is the storyboard; views/devices/ are the SceneKit
-- prefabs; Choreography.lua keys the camera and the devices; CoinQuest.lua
-- replays the real game; Score.lua is the music. captures/ comes from
-- capture.lua (make promo-reel-captures).
package.path = "modules/reel/?.lua;reels/promo/?.lua;" .. package.path
local Reel = require("Reel")
local Stage = require("Stage")
local C = require("Choreography")
local CoinQuest = require("CoinQuest")
local shots = require("shots")
local Score = require("Score")

local here = "reels/promo/"
local DURATION, SAMPLE_RATE = 30, 48000

local every = Reel.curves.every

local function join(...)
	local list = {}
	for _, part in ipairs({ ... }) do for _, t in ipairs(part) do table.insert(list, t) end end
	return list
end

-- The music's timeline, from the picture's (Score.lua).
local function music(data)
	local coins = {}
	for _, event in ipairs(data.quest.events) do
		if event.name == "coin" then table.insert(coins, event.time + C.QUEST.start) end
	end
	return {
		kicks = join(every(0.5, 1.0, 3.44), every(0.5, 3.5, 11.0), every(0.5, 14.0, 20.3), every(0.5, 20.5, 21.75),
			every(0.5, 21.8, 27.8), { 28.05 }),
		crashes = { 3.5, 14.0, 17.0, 21.8, 25.0, 28.05 },
		booms = { { 3.5, 0.9 }, { 11.05, 0.6 }, { 14.0, 0.5 }, { 21.8, 1.0 }, { 28.05, 0.9 } },
		risers = { { 2.3, 3.45 }, { 12.7, 13.95 }, { 20.5, 21.75 }, { 26.9, 27.95 } },
		whooshes = { { 0.75, 1.05 }, { 1.5, 1.8 }, { 1.85, 2.6 }, { 2.25, 2.55 }, { 2.95, 3.5 }, { 3.5, 4.4 },
			{ 13.0, 13.9 }, { 17.0, 17.5 }, { 21.2, 21.8 } },
		typing = { { from = 7.0, to = 7.55, count = 22 }, { from = 9.5, to = 10.05, count = 24 } },
		sends = { C.SHOT.send1, C.SHOT.send2 },
		coins = coins,
		hits = { 25.0, 25.5, 26.0, 26.5, 27.0 },
		logo = 28.05,
	}
end

local function load(template)
	local data = {
		root = io.popen("pwd"):read("l") .. "/",
		captures = Reel.captures(here .. "captures", "run make promo-reel-captures"),
		capturesDir = here .. "captures/",
	}
	data.environment = Stage.environment(Reel.native(), Reel.Pen)
	data.C = C
	-- The Sawmill, played by a scripted pad: up, five hops left along the
	-- open row to a coin, then down two to the next, saws running.
	local script, at = {}, 1.25
	for _, direction in ipairs({ "up", "left", "left", "left", "left", "left", "down", "down", "right", "right" }) do
		table.insert(script, { at, direction })
		at = at + 0.21
	end
	data.quest = CoinQuest.new({ level = 2, script = script, duration = C.SHOT.speed - C.QUEST.start + 0.5 })
	data.questStates = function(t)
		local states = data.quest:poses(t - C.QUEST.start)
		table.insert(states, C.questCamera(t))
		return states
	end
	data.shots = shots
	data.subframes = os.getenv("REEL_SUBFRAMES")
	return Reel.load(here .. "views/" .. (template or "Reel.etlua"), data), data
end

local function main(mode, ...)
	local args = { ... }
	if mode == "stills" and args[1] and args[2] then
		local reel = load(args[3])
		for time in args[2]:gmatch("[^,]+") do
			local t = tonumber(time)
			local path = string.format("%s/still-%05.2f.png", args[1], t)
			local started = os.clock()
			reel:still(t, path)
			print(path, string.format("%.2fs", os.clock() - started))
		end
	elseif mode == "render" and args[1] then
		local reel, data = load()
		local started = os.time()
		local left, right = Score.render(reel, music(data), DURATION, SAMPLE_RATE)
		local wav = os.tmpname() .. ".wav"
		Reel.writeWav(wav, SAMPLE_RATE, left, right)
		print(string.format("audio %ds", os.time() - started))
		local ok, frames = pcall(reel.movie, reel, args[1], {
			from = tonumber(args[2]), to = tonumber(args[3]), audio = wav,
			progress = function(done, total)
				if done % 30 == 0 or done == total then
					io.write(string.format("frame %d/%d %ds\n", done, total, os.time() - started))
					io.flush()
				end
			end,
		})
		os.remove(wav)
		if not ok then error(frames, 0) end
		print(string.format("wrote %s (%d frames)", args[1], frames))
	else
		io.stderr:write("usage: init.lua stills <dir> <t1,t2,…> [template] | render <out.mov> [from to]\n")
		return 1
	end
	return 0
end

local ok, status = pcall(main, table.unpack(arg))
if not ok then
	io.stderr:write(tostring(status) .. "\n")
	os.exit(1)
end
os.exit(status)
