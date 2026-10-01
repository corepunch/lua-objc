local t = require("TestKit")
local function source(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

-- Exercise the public constructor with both local files and streamed assets.
local constructor = source("lua/embedded/UIKit.lua"):match("function UIKit.Image%(arg%)(.-)\nend")
local calls = {}
local bridge = {
	_image = function(light, dark)
		table.insert(calls, { light, dark })
		return {}
	end,
	_imageData = function(light, dark)
		table.insert(calls, { light, dark })
		return {}
	end,
}
local UIKit = {}
assert(load("UIKit.Image = function(arg)" .. constructor .. "\nend", "Image", "t", {
	UIKit = UIKit, bridge = bridge, type = type, tostring = tostring, error = error,
	applyLayout = function(view) return view end,
}))()
local image = UIKit.Image { path = "light.jpg", darkPath = "dark.jpg", resizable = true, contentMode = "fill" }
t.assertEqual(calls[1][1], "light.jpg", "local light path reaches native image")
t.assertEqual(calls[1][2], "dark.jpg", "local dark path reaches native image")
t.expect(image.fillWidth and image.fillHeight, "appearance images preserve resizable layout")
t.assertEqual(image.contentModeName, "fill", "appearance images preserve scaling")
bridge._readFile = function(path) return "bytes:" .. path end
UIKit.Image { path = "light.jpg", darkPath = "dark.jpg" }
t.assertEqual(calls[2][1], "bytes:light.jpg", "streamed light bytes reach native image")
t.assertEqual(calls[2][2], "bytes:dark.jpg", "streamed dark bytes reach native image")
UIKit.Image("light.jpg")
t.expect(calls[3][2] == nil, "a single image needs no dark variant")
bridge._readFile = function(path)
	if path == "dark.jpg" then return nil, "missing dark image" end
	return "light bytes"
end
t.assertThrows(function() UIKit.Image { path = "light.jpg", darkPath = "dark.jpg" } end,
	"missing streamed dark assets fail before constructing a view")
local native = source("src/uikit/views.m")
t.expect(native:find("registerImage:light", 1, true) and native:find("registerImage:dark", 1, true),
	"both appearances belong to one native image asset")
os.exit(t.summary() and 0 or 1)
