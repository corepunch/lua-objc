local t = require("TestKit")

local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")
local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local appkitNative = assert(io.open("src/appkit/views.m", "r")):read("*a")
local uikitNative = assert(io.open("src/uikit/views.m", "r")):read("*a")

t.expect(xml:find("SystemImage", 1, true) ~= nil,
	"XML registers native system images")
t.expect(appkitNative:find("imageWithSystemSymbolName", 1, true) ~= nil,
	"AppKit creates real SF Symbol images")
t.expect(uikitNative:find("systemImageNamed", 1, true) ~= nil,
	"UIKit creates real SF Symbol images")
t.expect(xml:find("accessibilityLabel", 1, true) ~= nil,
	"System images preserve accessibility labels")

os.exit(t.summary() and 0 or 1)
