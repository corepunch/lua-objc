local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local native = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(src:find("function UIKit.MaterialView", 1, true) ~= nil,
	"UIKit exposes MaterialView")
t.expect(native:find("UIVisualEffectView", 1, true) ~= nil
		and native:find("UIBlurEffectStyleSystemMaterial", 1, true) ~= nil,
	"UIKit MaterialView uses native visual effect material")
t.expect(native:find("layout_recursive(self.luaContent", 1, true) ~= nil,
	"UIKit MaterialView lays out its native child")
t.expect(bridge:find('{"_materialView", bridge_UIKitControls_materialView}', 1, true) ~= nil,
	"UIKit MaterialView bridge is registered")
t.expect(xml:find("MaterialView =", 1, true) ~= nil,
	"XML registers MaterialView")

os.exit(t.summary() and 0 or 1)
