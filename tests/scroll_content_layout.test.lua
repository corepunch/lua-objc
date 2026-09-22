_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

local first = ns.Text { "First", fixedHeight = 100 }
local second = ns.Text { "Second", fixedHeight = 100 }
local content = ns.VStack { spacing = 12, first, second }
local scroll = ns.ScrollView { content = content }
scroll.frameSize = ns.Size(300, 80)
scroll:layout(300)
t.assertEqual(content.size.width, scroll.contentSize.width, "vertical document follows native viewport width")
t.assertEqual(content.size.height, 212, "vertical document measures content beyond viewport")
t.assertEqual(first.size.height, 100, "first row survives scroll layout")
t.assertEqual(second.size.height, 100, "second row survives scroll layout")
t.assertEqual(scroll.contentView.bounds.origin.y, content.size.height - scroll.contentSize.height, "new document begins at top after scroller tiling")
scroll.frameSize = ns.Size(200, 300)
scroll:layout(200)
t.assertEqual(content.size.width, scroll.contentSize.width, "document follows narrower viewport")
t.assertEqual(content.size.height, scroll.contentSize.height, "short content fills viewport")
scroll.frameSize = ns.Size(200, 80)
scroll:layout(200)
t.assertEqual(scroll.contentView.bounds.origin.y, content.size.height - scroll.contentSize.height,
	"shrinking viewport preserves reading position at top")
t.expect(scroll.contentView.clipsToBounds, "native clip view contains overflowing document")
-- A native window resize adjusts the clip before the document is remeasured.
-- Preserve a reader's offset as well as the special at-top position.
scroll.contentView.bounds = ns.Rect(ns.Point(0, content.size.height - scroll.contentSize.height - 40),
	scroll.contentSize)
scroll.frameSize = ns.Size(220, 110)
scroll:layout(220)
t.assertEqual(content.size.height - scroll.contentView.bounds.origin.y - scroll.contentSize.height, 40,
	"growing viewport preserves the reader's distance from top")
scroll.frameSize = ns.Size(200, 80)
scroll:layout(200)
t.assertEqual(content.size.height - scroll.contentView.bounds.origin.y - scroll.contentSize.height, 40,
	"shrinking viewport preserves the reader's distance from top")
local tab = ns.TabView { tabs = {{ __tab = true, title = "Content", content = scroll }} }
tab.frameSize = ns.Size(640, 720)
tab:layout(640)
t.expect(scroll.size.width > 500, "native tab sizes its selected scroller")
t.assertEqual(content.size.width, scroll.contentSize.width, "layout traverses native tab and clip containers")
t.assertEqual(content.size.height, scroll.contentSize.height, "nested document fills native tab viewport")
os.exit(t.summary() and 0 or 1)
