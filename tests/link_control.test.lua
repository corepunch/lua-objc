local t = require("TestKit")

local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")
local appkitNative = assert(io.open("src/appkit/controls.m", "r")):read("*a")
local uikitNative = assert(io.open("src/uikit/constructors.m", "r")):read("*a")

t.expect(appkit:find("function AppKit.Link", 1, true) ~= nil,
	"AppKit exposes Link")
t.expect(uikit:find("function UIKit.Link", 1, true) ~= nil,
	"UIKit exposes Link")
t.expect(xml:find("Link =", 1, true) ~= nil, "XML registers Link")
t.expect(appkitNative:find("NSWorkspace sharedWorkspace", 1, true) ~= nil,
	"AppKit Link opens URLs through NSWorkspace")
t.expect(uikitNative:find("UIApplication sharedApplication", 1, true) ~= nil,
	"UIKit Link opens URLs through UIApplication")

os.exit(t.summary() and 0 or 1)
