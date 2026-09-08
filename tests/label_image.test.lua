local t = require("TestKit")
local appkit = require("AppKit")

local appkitLabel = appkit.Text {
		"Settings", systemImage = "gear", accessibilityLabel = "Settings",
}

t.expect(appkitLabel ~= nil, "AppKit labels compose a native system image")

local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")
t.expect(assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
	:find("UIKit.SystemImage", 1, true) ~= nil,
	"UIKit labels compose a native system image")
t.expect(xml:find("systemImage = \"str\"", 1, true) ~= nil,
	"XML Label forwards systemImage")
t.expect(xml:find("iconSize   = \"num\"", 1, true) ~= nil,
	"XML Label forwards icon sizing")

os.exit(t.summary() and 0 or 1)
