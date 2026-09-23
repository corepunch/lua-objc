_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

local footer = ns.Text("Footer")
local list = ns.List {
	columns = { { id = "title", title = "" } },
	data = { { title = "A" }, { title = "B" } },
	header = false,
	flexGrow = 1,
	fillWidth = true,
}
local inner = ns.VStack {
	ns.Text("Header"), list, footer,
	fillWidth = true, fillHeight = true,
}
local outer = ns.VStack { inner, fillWidth = true, fillHeight = true }

outer.size = ns.Size(500, 480)
outer:layout(500)
outer.size = ns.Size(400, 360)
outer:layout(400)

t.expect(inner.frame.size.height <= 360,
	"a filled nested stack gives height back when its parent shrinks")
t.expect(footer.frame.origin.y >= 0,
	"fixed footer remains inside the resized stack")
t.expect(list.frame.size.height > 0,
	"flexible primary list keeps usable height")

os.exit(t.summary() and 0 or 1)
