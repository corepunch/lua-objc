_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- A donut's center total must never wrap ("110.4" over "GB"): the hole is
-- narrower than the total at its declared size, so every center label is one
-- line and shrinks to fit.
local _, refs = xml.renderFile("apps/diskmap/views/Kinds.etlua", {
	header = {icon = "square.grid.2x2.fill", color = "systemPink", title = "File Types"},
	kinds = {{id = "other", bytes = 1, color = "systemBlue", name = "Other files"}},
	extensionsDetail = "The twelve extensions that use the most space",
	total = "110.4 GB", summary = "110.4 GB in files across 1 kinds",
	headline = {id = "other", title = "Other files", advice = ""}, accessibilityLabel = "File types",
	actions = {openKind = function() end, kindMenu = function() return {} end, kind_other = function() end,
		selectKind = function() end, chartSelect = function() end, chartHover = function() end},
}, ns)
local chart = refs.kindsChart
chart:layout(chart.frame.size.width)
local label = refs.kindsTotal
t.assertEqual(label.maximumNumberOfLines, 1, "the File Types total is a single line")
t.expect(label.font.pointSize < 22, "a wide total shrinks rather than wrapping")
t.expect(label.frame.size.height < label.font.pointSize * 2, "the total occupies one line of height")

-- Every label drawn inside a SectorChart in an app view declares lines="1"
-- and a minimumScaleFactor.
for path in io.popen("ls apps/*/views/*.etlua demo/*/views/*.etlua 2>/dev/null"):lines() do
	local source = io.open(path):read("a")
	for body in source:gmatch("<SectorChart.-</SectorChart>") do
		for tag in body:gmatch("<Label%s.-/>") do
			t.expect(tag:find('lines="1"', 1, true) and tag:find("minimumScaleFactor=", 1, true),
				path .. ": chart center label is one line and shrinks to fit: " .. tag)
		end
	end
end

os.exit(t.summary() and 0 or 1)
