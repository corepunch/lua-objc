local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local native = assert(io.open("src/uikit/navigation.m", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(src:find("function UIKit.NavigationLink", 1, true) ~= nil,
	"UIKit exposes NavigationLink")
t.expect(src:find("hidesNavigationBar", 1, true) ~= nil
		and src:find("prefersLargeTitles", 1, true) ~= nil,
	"NavigationStack forwards native title-bar configuration")
t.expect(native:find("pushViewController:self.destination", 1, true) ~= nil,
	"NavigationLink pushes a native destination controller")
t.expect(bridge:find('{"_navigationLink", bridge_UIKitNavigation_link}', 1, true) ~= nil,
	"NavigationLink bridge is registered")
t.expect(xml:find("NavigationStack =", 1, true) ~= nil
		and xml:find("NavigationLink =", 1, true) ~= nil,
	"XML registers navigation tags")

os.exit(t.summary() and 0 or 1)
