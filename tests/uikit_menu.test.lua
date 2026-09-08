local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local native = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(src:find("function UIKit.Menu", 1, true) ~= nil,
	"UIKit exposes Menu")
t.expect(native:find("UIMenu", 1, true) ~= nil
		and native:find("showsMenuAsPrimaryAction", 1, true) ~= nil,
	"UIKit Menu uses native UIMenu presentation")
t.expect(native:find("UIMenuElementAttributesDestructive", 1, true) ~= nil,
	"UIKit Menu maps destructive role natively")
t.expect(bridge:find('{"_menu", bridge_UIKitControls_menu}', 1, true) ~= nil,
	"UIKit Menu bridge is registered")
t.expect(xml:find("Menu =", 1, true) ~= nil
		and xml:find("MenuItem =", 1, true) ~= nil,
	"XML registers Menu and MenuItem")

os.exit(t.summary() and 0 or 1)
