local t = require("TestKit")
local ns = require("AppKit")

local stack = ns.ZStack {
	padding = 8,
	alignment = "center",
	ns.Text({ "back", size = 20 }),
	ns.Text("front"),
}

t.expect(stack ~= nil, "AppKit ZStack constructs a native container")
t.expect(stack:add(ns.Text("nested")) == nil, "AppKit ZStack accepts nested children")

local constructors = assert(io.open("src/appkit/constructors.m", "r")):read("*a")
local layout = assert(io.open("src/appkit/layout.m", "r")):read("*a")
t.expect(constructors:find("LayoutAxisZStack", 1, true) ~= nil,
	"AppKit exports ZStack layout metadata")
t.expect(layout:find("case LayoutAxisZStack", 1, true) ~= nil,
	"AppKit lays out ZStack children as overlays")

os.exit(t.summary() and 0 or 1)
