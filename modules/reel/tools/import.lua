-- ./lua-objc modules/reel/tools/import.lua <screenshot.png> <layout.xml> <out> <light|dark> [width height]
-- Stores one window capture as <out>.jpg (the window from a `--screenshot`)
-- and <out>.layout.xml (the `--dump-layout`, pruned to what reels read).
package.path = "modules/reel/?.lua;" .. package.path
local Reel = require("Reel")

local screenshot, dump, output, appearance = arg[1], arg[2], arg[3], arg[4]
if not (screenshot and dump and output and appearance) then
	io.stderr:write("usage: import.lua <screenshot.png> <layout.xml> <out> <light|dark> [width height]\n")
	os.exit(1)
end
local expected = arg[5] and { tonumber(arg[5]), tonumber(arg[6]) } or nil
local ok, err = pcall(Reel.importCapture, screenshot, dump, output, appearance, expected)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	os.exit(1)
end
os.exit(0)
