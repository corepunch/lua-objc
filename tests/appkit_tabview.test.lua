local t = require("TestKit")

local src = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local bindings = assert(io.open("src/appkit/bindings.m", "r")):read("*a")

t.expect(src:find("tv:selectTab(props.selected)", 1, true) ~= nil,
	"AppKit TabView applies declarative selection")
t.expect(src:find("tv:onChange(props.onChange)", 1, true) ~= nil,
	"AppKit TabView forwards selection changes")
t.expect(bindings:find("bridge_NSTabView_selectTab", 1, true) ~= nil
		and bindings:find("bridge_NSTabView_onChange", 1, true) ~= nil,
	"AppKit TabView has native selection and callback bindings")

os.exit(t.summary() and 0 or 1)
