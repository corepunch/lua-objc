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

local focused = false
local field = ns.TextField {
	placeholder = "Command",
	onFocus = function() focused = true end,
}
ns._textFieldTestFocus(field)
t.expect(focused, "beginning editing reports that the keyboard is showing")

os.exit(t.summary() and 0 or 1)
