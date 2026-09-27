-- ./lua-objc modules/reel/tools/import.lua <screenshot.png> <out.jpg> <light|dark> [width height]
-- Keeps the window from a `--screenshot` capture and stores it as JPEG.
package.path = "modules/reel/?.lua;" .. package.path
local Reel = require("Reel")

local input, output, appearance = arg[1], arg[2], arg[3]
if not (input and output and appearance) then
	io.stderr:write("usage: import.lua <screenshot.png> <out.jpg> <light|dark> [width height]\n")
	os.exit(1)
end
local expected = arg[4] and { tonumber(arg[4]), tonumber(arg[5]) } or nil
local ok, err = pcall(Reel.importCapture, input, output, appearance, expected)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	os.exit(1)
end
os.exit(0)
