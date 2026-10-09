_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- A donut's center total must never wrap ("110.4" over "GB"): the hole is
-- narrower than the total at its declared size, so every center label is one
-- line and shrinks to fit.
local _, refs = xml.renderFile("apps/diskmap/views/sections/Breakdown.etlua", {
	style = "rings", title = "File Types", detail = "110.4 GB in files",
	marks = {{id = "other", value = 1, color = "systemBlue", label = "Other files"}},
	legend = {}, center = {title = "110.4 GB", detail = "in files"},
	actions = {toggleBreakdown = function() end, chartSelect = function() end, chartHover = function() end, chartCenter = function() end},
}, ns)
local chart = refs.breakdownChart
chart:layout(chart.frame.size.width)
local label = refs.breakdownTotal
t.assertEqual(label.maximumNumberOfLines, 1, "the total is a single line")
t.expect(label.frame.size.height < label.font.pointSize * 2, "the total occupies one line of height")

-- Every label drawn inside a SectorChart in an app view declares lines="1"
-- and a minimumScaleFactor.
for path in io.popen("find apps/*/views demo/*/views -name '*.etlua' 2>/dev/null"):lines() do
	local source = io.open(path):read("a")
	for body in source:gmatch("<SectorChart.-</SectorChart>") do
		for tag in body:gmatch("<Label%s.-/>") do
			t.expect(tag:find('lines="1"', 1, true) and tag:find("minimumScaleFactor=", 1, true),
				path .. ": chart center label is one line and shrinks to fit: " .. tag)
		end
	end
end

os.exit(t.summary() and 0 or 1)
