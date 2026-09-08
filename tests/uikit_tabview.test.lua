local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")

t.expect(src:find("bridge._tabViewSelectTab(tbc, props.selected)", 1, true) ~= nil,
	"UIKit TabView applies declarative selection")
t.expect(src:find("bridge._tabViewOnChange(tbc, props.onChange)", 1, true) ~= nil,
	"UIKit TabView forwards selection changes")
t.expect(bridge:find("bridge_UIKitTabView_selectTab", 1, true) ~= nil
		and bridge:find("bridge_UIKitTabView_onChange", 1, true) ~= nil,
	"UIKit TabView has native selection and callback bridges")

os.exit(t.summary() and 0 or 1)
