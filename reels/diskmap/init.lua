-- Diskmap showreel, rendered with the Reel package (modules/reel).
--
--   ./lua-objc reels/diskmap/init.lua stills <out dir> <t1,t2,…>
--   ./lua-objc reels/diskmap/init.lua render <out.mov> [from to]
--
-- The storyboard is views/Reel.etlua (scenes are partials), bespoke shots
-- are shots.lua, the music is Score.lua; captures/ comes from the capture
-- plan capture.lua.
package.path = "modules/reel/?.lua;reels/diskmap/?.lua;" .. package.path
local Reel = require("Reel")
local Score = require("Score")
local shots = require("shots")

local here = "reels/diskmap/"
local every = Reel.curves.every
local DURATION, SAMPLE_RATE = 34, 48000

local function join(...)
	local list = {}
	for _, part in ipairs({ ... }) do for _, t in ipairs(part) do table.insert(list, t) end end
	return list
end

-- The kick drum: four on the floor through the drops, a broken pattern in
-- the breakdown. The stage lights, the wall and the score read the same list.
local kicks = join(every(0.5, 6, 24), { 24, 24.75, 25.5, 26, 26.75, 27.5 }, every(0.5, 28, 30))

local data = {
	kicks = kicks,
	-- Diskmap's categories as the logo ring: share of the circle, colour.
	logo = { { 41, 0xB23FD9 }, { 20, 0x3B82F6 }, { 13, 0x34C759 }, { 8, 0xFF453A }, { 8, 0x0A84FF }, { 6, 0x5E5CE6 }, { 4, 0x8E8E93 } },
	-- The light/dark divider hops on the beat: {from, to, x}.
	dividerKeys = { { 24.0, 24.42, 960 }, { 25.0, 25.3, 1360 }, { 25.5, 25.8, 580 }, { 26.25, 26.55, 960 }, { 27.5, 27.85, 1990 } },
	dividerMoves = { 24.0, 25.0, 25.5, 26.25 },
	flips = { 26.0, 27.0 },
	wallPages = { "overview-light", "cleanup-dark", "largest-light", "kinds-dark", "files-light", "map-dark",
		"treemap-light", "guide-dark", "files-dark", "overview-dark", "updates-light", "largest-dark" },
	shots = shots,
}

local music = {
	kicks = kicks, drop = 6, breakdown = 24, lift = 28, logo = 30, finish = 30,
	claps = { 25.0, 27.0 },
	crashes = { 6.0, 10.0, 14.0, 18.0, 22.0, 24.0, 28.0, 30.0 },
	risers = { { 4.6, 5.95 }, { 28.6, 29.95 } },
	rolls = { { 5.0, 5.93 }, { 29.0, 29.93 } },
	booms = { { 6, 0.9 }, { 30, 0.9 }, { 28, 0.4 } },
}

local function load()
	data.captures = Reel.captures(here .. "captures", "run make diskmap-reel-captures")
	return Reel.load(here .. "views/Reel.etlua", data)
end

local function main(mode, ...)
	local args = { ... }
	if mode == "stills" and args[1] and args[2] then
		local reel = load()
		for time in args[2]:gmatch("[^,]+") do
			local t = tonumber(time)
			local path = string.format("%s/still-%05.2f.png", args[1], t)
			reel:still(t, path)
			print(path)
		end
	elseif mode == "render" and args[1] then
		local reel = load()
		local started = os.time()
		local left, right = Score.render(reel, music, DURATION, SAMPLE_RATE)
		local wav = os.tmpname() .. ".wav"
		Reel.writeWav(wav, SAMPLE_RATE, left, right)
		print(string.format("audio %ds", os.time() - started))
		local ok, frames = pcall(reel.movie, reel, args[1], {
			from = tonumber(args[2]), to = tonumber(args[3]), audio = wav,
			progress = function(done, total)
				if done % 90 == 0 or done == total then
					io.write(string.format("frame %d/%d %ds\n", done, total, os.time() - started))
					io.flush()
				end
			end,
		})
		os.remove(wav)
		if not ok then error(frames, 0) end
		print(string.format("wrote %s (%d frames)", args[1], frames))
	else
		io.stderr:write("usage: init.lua stills <dir> <t1,t2,…> | render <out.mov> [from to]\n")
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
