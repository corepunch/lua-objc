-- Diskmap showreel, rendered with the Reel package (modules/reel).
--
--   ./lua-objc reels/diskmap/init.lua stills <out dir> <t1,t2,…>
--   ./lua-objc reels/diskmap/init.lua render <out.mov> [from to]
--
-- The storyboard is views/Reel.etlua; captures/ comes from capture.sh.
package.path = "modules/reel/?.lua;" .. package.path
local Reel = require("Reel")

local here = "reels/diskmap/"
local every = Reel.curves.every

-- The kick drum: four on the floor through the drops, a broken pattern in
-- the breakdown. The stage lights and (later) the score read the same list.
local kicks = every(0.5, 4, 20)
for _, t in ipairs({ 20, 20.75, 21.5, 22, 22.75, 23.5 }) do table.insert(kicks, t) end
for _, t in ipairs(every(0.5, 24, 26)) do table.insert(kicks, t) end

local function load()
	return Reel.load(here .. "views/Reel.etlua", {
		captures = Reel.captures(here .. "captures"),
		kicks = kicks,
	})
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
		local started = os.clock()
		local frames = reel:movie(args[1], {
			from = tonumber(args[2]), to = tonumber(args[3]),
			progress = function(done, total)
				if done % 30 == 0 or done == total then
					io.write(string.format("frame %d/%d %.0fs\n", done, total, os.clock() - started))
				end
			end,
		})
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
