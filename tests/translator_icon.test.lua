-- The selected translator artwork is a full-size, opaque iOS icon;
-- Apple's asset compiler supplies the device sizes and system mask.
_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local root = "apps/translator/Assets.xcassets/AppIcon.appiconset/"
local function read(path)
	local file = assert(io.open(path, "rb"))
	local data = file:read("a")
	file:close()
	return data
end
local catalog = ns.json_parse(read(root .. "Contents.json"))
t.assertEqual(#catalog.images, 1, "one universal source supplies the iOS icon")
local entry = catalog.images[1]
t.assertEqual(entry.platform, "ios", "the icon targets the translator's iPhone app")
t.assertEqual(entry.idiom, "universal", "the icon supports both device families")
t.assertEqual(entry.size, "1024x1024", "the catalog declares full-resolution artwork")
local data = read(root .. entry.filename)
t.assertEqual(data:sub(1, 8), "\137PNG\13\10\26\10", "the source is a PNG")
local width, height = string.unpack(">I4I4", data, 17)
t.assertEqual(width, 1024, "the artwork is 1024 pixels wide")
t.assertEqual(height, 1024, "the artwork is square")
t.assertEqual(data:byte(26), 2, "RGB artwork has no alpha channel")
t.expect(not data:find("tRNS", 1, true), "the icon has no transparent color")
os.exit(t.summary() and 0 or 1)
