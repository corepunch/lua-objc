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
local Todo = require("Todo")
local Score = require("Score")
local Edits = require("Edits")
local Conversation = require("Conversation")

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
	local S = C.SHOT
	return {
		kicks = join(every(0.5, 0.5, 3.55), every(0.5, 3.6, 11.75), every(0.5, 13.0, 17.6), every(0.5, 18.5, 19.45),
			every(0.5, S.cut, 23.6), { S.logo }),
		crashes = { 3.6, 13.0, S.cut, S.logo },
		booms = { { 3.6, 0.9 }, { 11.75, 0.6 }, { S.cut, 1.0 }, { S.logo, 0.9 } },
		risers = { { 2.4, 3.55 }, { 12.5, 12.97 }, { 18.2, 19.47 }, { 24.6, 25.97 } },
		whooshes = { { 2.6, 3.6 }, { 5.0, 5.55 }, { 6.2, 6.8 }, { 9.95, 10.35 }, { 12.5, 13.4 },
			{ 17.6, 18.45 }, { 18.9, 19.5 }, { 23.6, 25.0 } },
		typing = { { from = 4.0, to = 4.7, count = 22 }, { from = 7.25, to = 7.8, count = 24 } },
		sends = { S.send1, S.send2, S.send3 },
		pops = { 0.5, 1.0, 1.5, S.change1, S.change2, S.checked, S.layers[1], S.layers[2], S.layers[3], S.change3, S.opened },
		taps = { S.tap, S.tapOpen },
		coins = coins,
		logo = S.logo,
	}
end

local function screens(dir)
	local S = C.SHOT
	local rows = Todo.states()
	local phones = {
		pair = {
			dir = dir, rows = rows,
			timeline = {
				{ at = 0, state = "v0", assemble = { 0.5, 1.0, 1.0, 1.5 } },
				{ at = S.change1, state = "v1" }, { at = S.change2, state = "v2" },
				{ at = S.checked, state = "checked" }, { at = S.change3, state = "filtered" },
				{ at = S.opened, state = "open" },
			},
			taps = {
				-- The checkbox of the first open task.
				{ at = S.tap, aim = { "v2", "task/2", 0.075, 0.5 } },
				-- "Open", the filter's middle segment.
				{ at = S.tapOpen, aim = { "filtered", "filter", 0.5, 0.5 } },
			},
		},
		hero = { dir = dir, rows = rows, timeline = { { at = 0, state = "open" } } },
	}
	local studios = {
		pair = {
			dir = dir,
			sends = { { at = S.send1, typeFrom = 4.0, typeTo = 4.7, fly = 0.3 }, { at = S.send2, typeFrom = 7.25, typeTo = 7.8 } },
			previews = { { at = S.change1, version = 1 }, { at = S.change2, version = 2 } },
		},
		hero = {
			dir = dir,
			sends = { { at = -3, typeFrom = -4, typeTo = -4 }, { at = -2, typeFrom = -4, typeTo = -4 }, { at = -1, typeFrom = -4, typeTo = -4 } },
			previews = { { at = -1, version = 3 } },
		},
	}
	return phones, studios
end

-- The layers of MVC the filter edit lands in, from its own patch: each
-- changed file with its role and its first lines of code.
local LAYERS = {
	["Model.lua"] = { role = "Model", note = "data, queries, rules", color = 0x7B8CFF },
	["Controller.lua"] = { role = "Controller", note = "actions", color = 0xB86BFF },
	["views/Content.etlua"] = { role = "View", note = "etlua template", color = 0xFF7AB8 },
}
local function layers()
	local app = Edits.todo
	local list = {}
	for _, file in ipairs(Conversation.files(here .. "edits/" .. app.edits[3].patch .. ".patch")) do
		local name = file.path:sub(#app.dir + 2)
		local layer = LAYERS[name] or error("promo: no layer for " .. name)
		local lines = {}
		local added = {}
		for _, line in ipairs(file.lines) do if line.sign == "+" then table.insert(added, line) end end
		for _, line in ipairs(Conversation.excerpt(added, 3)) do table.insert(lines, (line:gsub("^%+ ", ""))) end
		table.insert(list, { role = layer.role, note = layer.note, color = layer.color, file = name:match("[^/]+$"),
			delta = "+" .. file.added .. (file.removed > 0 and (" −" .. file.removed) or ""), lines = lines })
	end
	return list
end

local function load(template)
	local data = {
		root = io.popen("pwd"):read("l") .. "/",
		captures = Reel.captures(here .. "captures", "run make promo-reel-captures"),
		capturesDir = here .. "captures/",
	}
	data.environment = Stage.environment(Reel.native(), Reel.Pen)
	data.C = C
	-- Green Meadow, played by a scripted pad: walk up the opening ramp
	-- and follow the first two coins onto the broad hub.
	local script = { { 1.25, "up", 0.7 } }
	data.quest = CoinQuest.new({ level = 1, script = script, duration = C.SHOT.hero - C.QUEST.start + 0.5 })
	data.questStates = function(t)
		local states = data.quest:poses(t - C.QUEST.start)
		table.insert(states, C.questCamera(t))
		return states
	end
	data.shots = shots
	data.layers = layers()
	data.phones, data.studios = screens(data.capturesDir)
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
