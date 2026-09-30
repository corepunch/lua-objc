_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- AppKit has no UIPageControl; <PageControl> draws its dots from SF Symbols
-- with the same attributes, so one template serves both platforms.
local dots = xml.render('<PageControl numberOfPages="5" currentPage="2" />', {}, ns)
t.assertEqual(dots.numberOfPages, 5, "one dot per page")
t.assertEqual(dots.currentPage, 2, "currentPage is zero-based")
local function size(view) local value = view.intrinsicContentSize; return value.width, value.height end
local width, height = size(dots)
t.expect(width > 0 and height > 0, "the dots have a size of their own")

dots.currentPage = 9
t.assertEqual(dots.currentPage, 4, "currentPage stays within the pages")
dots.currentPage = -1
t.assertEqual(dots.currentPage, 0, "and not below the first")

dots.numberOfPages = 3
local narrower = size(dots)
t.expect(narrower < width, "fewer pages, fewer dots")
dots.numberOfPages = 0
t.assertEqual((size(dots)), 0, "no pages, no dots")

local changed
local clickable = xml.render('<PageControl numberOfPages="3" onChange="changed" />', {actions = {changed = function(page) changed = page end}}, ns)
t.expect(clickable ~= nil and changed == nil, "onChange binds without firing")

os.exit(t.summary() and 0 or 1)
