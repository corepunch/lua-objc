_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")

local function tallScroll()
	local first = ns.Text { "First", fixedHeight = 100 }
	local second = ns.Text { "Second", fixedHeight = 100 }
	second.accessibilityIdentifier = "second"
	local content = ns.VStack { spacing = 12, first, second }
	local scroll = ns.ScrollView { content = content, scrollOnKeyboard = true }
	return scroll, content
end

local scroll, content = tallScroll()
scroll:scrollTo("bottom", false)
scroll.frameSize = ns.Size(300, 80)
scroll:layout(300)
t.assertEqual(scroll.contentView.bounds.origin.y, 0,
	"a pending scroll-to-bottom survives the layout that measures the transcript")
t.expect(content.size.height > scroll.contentSize.height, "fixture is tall enough to scroll")

scroll:scrollTo("top", false)
local top = content.size.height - scroll.contentSize.height
t.assertEqual(scroll.contentView.bounds.origin.y, top, "scrollTo top shows the start of the transcript")
scroll.frameSize = ns.Size(300, 60)
scroll:layout(300)
t.assertEqual(scroll.contentView.bounds.origin.y, content.size.height - scroll.contentSize.height,
	"leaving the bottom keeps the reader's place when the viewport shrinks")

scroll:scrollTo("bottom", false)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "scrollTo bottom shows the latest line")
scroll:scrollTo("second", false)
t.expect(scroll.contentView.bounds.origin.y < top / 2, "scrollTo an id brings that line to the bottom")

-- scrollTo(id, animated, "top") is SwiftUI's scrollTo(_:anchor: .top).
local third = ns.Text { "Third", fixedHeight = 100 }
third.accessibilityIdentifier = "third"
content:add(third)
scroll:scrollTo("second", false, "top")
local tall = content.size.height
t.expect(tall > 300, "scrollTo measures content added since the last layout")
t.assertEqual(scroll.contentView.bounds.origin.y, tall - 112 - scroll.contentSize.height,
	"a top anchor brings the line's top edge to the top of the viewport")
scroll:scrollTo("third", false, "top")
t.assertEqual(scroll.contentView.bounds.origin.y, 100 - scroll.contentSize.height,
	"a line taller than the viewport is read from its top")
scroll.frameSize = ns.Size(300, 150)
scroll:scrollTo("third", false, "top")
t.assertEqual(scroll.contentView.bounds.origin.y, 0,
	"a top anchor stops at the end of the content when less than a viewport follows")
scroll.frameSize = ns.Size(300, 60)
scroll:scrollTo("bottom", true)
t.assertEqual(scroll.contentView.bounds.origin.y, 0, "an animated scroll still arrives")
content:add(ns.Text { "Fourth", fixedHeight = 100 })
scroll:layout(300)
t.assertEqual(scroll.contentView.bounds.origin.y, 112,
	"an animated scroll leaves nothing for a later layout to jump to")

local focused = false
local field = ns.TextField {
	placeholder = "Command",
	onFocus = function() focused = true end,
}
ns._textFieldTestFocus(field)
t.expect(focused, "beginning editing reports that the keyboard is showing")

os.exit(t.summary() and 0 or 1)
