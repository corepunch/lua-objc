local ns = require("AppKit")
local t = require("TestKit")

-- VStack: can create and add children without crashing

local ok = pcall(function()
	local v = ns.VStack {
		ns.Text "First",
		ns.Text "Second",
	}
end)
t.expect(ok, "VStack creates without error")

-- HStack: can create with Spacer

ok = pcall(function()
	local h = ns.HStack {
		ns.Text "Left",
		ns.Spacer(),
		ns.Text "Right",
	}
end)
t.expect(ok, "HStack creates without error")

-- Window with visible=false does not show

local win = ns.Window {
	title = "Headless Test",
	width = 400,
	height = 300,
	visible = false,
	ns.Text "Hello",
}

t.assertEqual(win.title, "Headless Test", "Window title is set")

-- Separator is an NSBox with separator style

local s = ns.Separator()
t.assertEqual(s.boxType, 2, "Separator has NSBoxSeparator boxType")

-- Spacer can be created

local sp = ns.Spacer()
t.expect(sp ~= nil, "Spacer creates successfully")

-- Layout modifiers support SwiftUI-like stack spacing and cross-axis fill

local filled = ns.Text {
	"Fill",
	fillWidth = true,
}
t.expect(filled.fillWidth, "fillWidth is retained")

local spaced = ns.VStack {
	spacing = 3,
	paddingHorizontal = 12,
	paddingVertical = 7,
	ns.Text "One",
	ns.Text "Two",
}
t.assertEqual(spaced.spacing, 3, "custom stack spacing is retained")
t.assertEqual(spaced.paddingHorizontal, 12, "horizontal padding is retained")
t.assertEqual(spaced.paddingVertical, 7, "vertical padding is retained")

-- Image layout uses the bridge's capped display size, not the source bitmap's
-- intrinsic dimensions, and remains proportional under a narrower proposal.

local cappedImage = ns.Image "tests/fixtures/oversized.svg"
ns.Window {
	width = 480,
	height = 300,
	visible = false,
	ns.VStack {
		alignment = "leading",
		cappedImage,
	},
}
t.assertSize(cappedImage, 400, 200, "oversized image uses capped layout size")

local narrowImage = ns.Image "tests/fixtures/oversized.svg"
ns.Window {
	width = 300,
	height = 300,
	visible = false,
	ns.VStack {
		alignment = "leading",
		narrowImage,
	},
}
t.assertSize(narrowImage, 300, 150, "image scales proportionally in a narrow window")

-- ForEach composes data-driven children without adding placeholder views

ok = pcall(function()
	ns.VStack {
		ns.ForEach({ "One", "Two" }, function(value)
			return ns.Text(value)
		end),
	}
end)
t.expect(ok, "ForEach composes data-driven views")

local compound = ns.Button {
	title = "Open",
	subtitle = "A document",
	systemImage = "folder",
	style = "plain",
}
t.expect(compound ~= nil, "compound native button creates successfully")

-- List: add, remove, clear rows

local list = ns.List {
	width = 400,
	height = 200,
	columns = {
		{ id = "name", title = "Name", width = 200 },
		{ id = "role", title = "Role", width = 200 },
	},
}

local has_add = list["addRow"] ~= nil
t.expect(has_add, "List has add_row method")

local has_clear = list["clearRows"] ~= nil
t.expect(has_clear, "List has clear_rows method")

local has_loading = list["showLoading"] ~= nil
t.expect(has_loading, "List has show_loading method")

list:clearRows()
t.assertEqual(list.rowCount, 0, "New list has zero rows")

list:addRow{ name = "Alice", role = "Engineer" }
t.assertEqual(list.rowCount, 1, "After addRow: 1 row")

list:addRow{ name = "Bob", role = "Designer" }
t.assertEqual(list.rowCount, 2, "After second addRow: 2 rows")

list:removeRow(0)
t.assertEqual(list.rowCount, 1, "After removeRow(0): 1 row")

list:clearRows()
t.assertEqual(list.rowCount, 0, "After clearRows: 0 rows")

-- Loading spinner

list:showLoading()
list:hideLoading()
t.expect(true, "show_loading and hide_loading do not crash")

-- fetch infrastructure exists

t.expect(ns.fetch ~= nil, "fetch function exists")
t.expect(ns.fetch_json ~= nil, "fetch_json function exists")
t.expect(ns.json_parse ~= nil, "json_parse function exists")
t.expect(ns.async ~= nil, "async function exists")
t.expect(ns.sleep ~= nil, "sleep function exists")

-- JSON parsing

local parsed = ns.json_parse('{"key": 42, "name": "test"}')
t.assertEqual(parsed.key, 42, "json_parse: numeric value")
t.assertEqual(parsed.name, "test", "json_parse: string value")

os.exit(t.summary() and 0 or 1)
