local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local native = assert(io.open("src/uikit/presentation.m", "r")):read("*a")

t.expect(src:find("function UIKit.presentSheet", 1, true) ~= nil,
	"UIKit exposes native sheet presentation")
t.expect(src:find("function UIKit.dismiss", 1, true) ~= nil,
	"UIKit exposes native dismissal")
t.expect(native:find("UISheetPresentationController", 1, true) ~= nil
		and native:find("UIModalPresentationPageSheet", 1, true) ~= nil,
	"UIKit sheets use native page-sheet presentation")
t.expect(native:find("mediumDetent", 1, true) ~= nil
		and native:find("largeDetent", 1, true) ~= nil,
	"UIKit sheets map native detents")
t.expect(bridge:find('{"_presentSheet", bridge_UIKitPresentation_presentSheet}', 1, true) ~= nil
		and bridge:find('{"_dismiss", bridge_UIKitPresentation_dismiss}', 1, true) ~= nil,
	"UIKit presentation bridge is registered")

os.exit(t.summary() and 0 or 1)
