_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

local first = ns.VStack { ns.Text "Adventures" }
local second = ns.VStack { ns.Text "Settings" }
local tabs = ns.TabView { tabs = {
	{ __tab = true, title = "Adventures", content = first },
	{ __tab = true, title = "Settings", content = second },
} }
t.assertEqual(tabs.selectedTabViewItem.label, "Adventures",
	"adding tabs preserves the initial selection")
local root = ns.VStack { tabs }
root.frameSize = ns.Size(640, 720)
root:layout(640)
t.assertSize(tabs, 640, 720, "tab container consumes the content proposal")
tabs:selectTab(1)
tabs:addTab("Help", ns.Text "Help")
t.assertEqual(tabs.selectedTabViewItem.label, "Settings",
	"adding a tab does not change the user's selected tab")
root.frameSize = ns.Size(1000, 900)
root:layout(1000)
t.assertSize(tabs, 1000, 900, "tab container grows with the window")
root.frameSize = ns.Size(420, 360)
root:layout(420)
t.assertSize(tabs, 420, 360, "tab container shrinks with the window")
t.assertEqual(tabs.selectedTabViewItem.label, "Settings",
	"resize preserves selection")

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
