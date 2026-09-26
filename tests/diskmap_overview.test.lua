_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Overview = require("apps.diskmap.models.Overview")
local Developer = require("apps.diskmap.models.Developer")
local Guide = require("apps.diskmap.models.Guide")

local model = Model.new("/Users/test")
for id, bytes in pairs({["apps-system-other"] = 58e9, derived = 4.9e9, simulators = 11e9,
	["codex-cache"] = 10e9, downloads = 20e9}) do
	model.measurements[id] = {bytes = bytes, status = "complete"}
end
local disk = {totalKb = 494e9 / 1024, freeKb = 157e9 / 1024}

-- Summary: capacity comes from the volume, never from measured totals.
local summary = Overview.summary(model, disk)
t.assertEqual(summary.used, "337.0 GB", "used capacity is total minus free")
t.assertEqual(summary.caption, "of 494.0 GB used", "the chart caption names the volume size")
t.assertEqual(summary.subtitle, "157.0 GB free of 494.0 GB", "free space keeps the file system's meaning")
t.expect(not summary.lowSpace, "a third free is not low space")
t.expect(Overview.summary(model, {totalKb = 100, freeKb = 5}).lowSpace, "under 10% free is low space")
local unknown = Overview.summary(model, nil)
t.expect(not unknown.available and unknown.used == "—", "missing capacity is never shown as zero")

-- Chart: named categories, the unattributed residual, then free space.
local chart = Overview.chart(model, disk)
local total = 0
for _, mark in ipairs(chart.marks) do total = total + mark.value end
t.expect(math.abs(total - 494e9) < 1, "the ring accounts for the whole volume")
t.assertEqual(chart.marks[1].label, "Applications", "the largest category starts the ring")
t.assertEqual(chart.marks[#chart.marks].label, "Free", "free space ends the ring")
t.assertEqual(chart.marks[#chart.marks].color, "quaternaryLabel", "free space is the empty track color")
t.assertEqual(chart.marks[#chart.marks - 1].label, "Not attributed", "the residual is visible, not hidden")
t.assertEqual(chart.legend[1].share, "17%", "legend shares are of used capacity")
t.expect(chart.accessibilityLabel:find("Applications 58.0 GB", 1, true) ~= nil, "VoiceOver reads the chart as text")
local crowded = Model.new("/Users/test")
for index, id in ipairs({"apps-system-other", "derived", "codex-cache", "downloads", "user-caches", "trash-user",
	"mail", "messages", "books-library", "podcasts-library"}) do
	if crowded.resources:find(id) then crowded.measurements[id] = {bytes = index * 1e9, status = "complete"} end
end
local crowdedChart = Overview.chart(crowded, disk)
t.expect(#crowdedChart.legend <= 8, "at most seven categories and one aggregate are named")
t.assertEqual(#Overview.chart(model, {totalKb = 1, freeKb = 0}).marks, 0, "an overcount draws no partition")

-- Cleanup headline keeps rebuildable and review-first bytes apart.
local reclaim = Overview.reclaim(model)
t.assertEqual(reclaim.title, "14.9 GB rebuildable", "rebuildable candidates lead the headline")
t.expect(reclaim.detail:find("more to review", 1, true) ~= nil, "review candidates are counted separately")
t.assertEqual(Overview.reclaim(Model.new("/Users/test")).title, "No cleanup suggestions yet", "an empty inventory promises nothing")

-- Largest items rank individual resources with their semantic owner.
local largest = Overview.largest(model, disk, 3)
t.assertEqual(#largest, 3, "the ranking honours its limit")
t.assertEqual(largest[1].id, "apps-system-other", "largest item first")
t.assertEqual(largest[1].relative, 1, "bars compare items with the largest")
t.assertEqual(largest[2].id, "downloads", "ranking is by measured bytes")
t.assertEqual(largest[1].subtitle, "Applications › Installed applications", "each item names its owner")
t.assertEqual(largest[1].parentId, "apps-system", "items open in their owning group")
t.assertEqual(#Overview.largest(model, disk, nil, "derived"), 1, "search filters by name, owner and path")
t.assertEqual(#Overview.largest(model, disk, nil, "no such thing"), 0, "search can empty the ranking")
t.assertEqual(Overview.largest(model, disk, nil, "derived")[1].impact, "Rebuildable", "impact follows cleanup policy")
model.measurements.archives = {status = "denied"}
for _, row in ipairs(Overview.largest(model, disk)) do
	t.expect(row.id ~= "archives", "unmeasured resources are never ranked")
end

-- Category rows sort by size and keep catalog order for unmeasured ones.
local rows = Overview.categories(model, disk)
t.assertEqual(rows[1].id, "applications", "largest category first")
t.assertEqual(rows[1].relative, 1, "the largest category has a full bar")
t.assertEqual(rows[#rows].relative, nil, "unmeasured categories have no bar")
t.assertEqual(rows[1].children, nil, "overview rows are flat")

-- Developer tiles name catalog resources and route to managed destinations.
local developer = Developer.presentation(model)
t.assertEqual(#developer.tiles, #Developer.tiles, "every developer tile maps to a catalog resource")
local tiles = {}
for _, tile in ipairs(developer.tiles) do tiles[tile.id] = tile end
t.assertEqual(tiles.simulators.relative, 1, "the largest developer tile has a full gauge")
t.assertEqual(tiles.simulators.open, "simulators", "simulator devices open the device sheet")
t.assertEqual(tiles["xcode-app"].open, "sdks", "Xcode opens its SDK list")
t.assertEqual(tiles.derived.size, "4.9 GB", "tiles show measured sizes")
t.assertEqual(developer.total, "25.9 GB", "developer total includes AI coding tools")
for _, tile in ipairs(Developer.tiles) do
	t.expect(tile.open == "simulators" or tile.open == "sdks" or model.resources:find(tile.open) ~= nil,
		"developer tile opens a registered destination: " .. tile.id)
end

-- The guide cites only registered resources and measures them live.
local topics = 0
for _, chapter in ipairs(Guide.chapters) do
	for _, topic in ipairs(chapter.topics) do
		topics = topics + 1
		t.expect(topic.what and topic.why and topic.action and topic.summary, "guide topic is complete: " .. topic.id)
		for _, id in ipairs(topic.resources or {}) do
			t.expect(model.resources:find(id) ~= nil, "guide topic " .. topic.id .. " cites registered resource " .. id)
		end
		if topic.open and topic.open ~= "simulators" and topic.open ~= "updates" then
			t.expect(model.resources:find(topic.open) ~= nil, "guide topic " .. topic.id .. " opens a registered category")
		end
	end
end
local guide = Guide.presentation(model, "")
t.assertEqual(guide.count, topics, "an empty search shows every topic")
for _, id in ipairs({"preboot", "updates", "vm", "snapshots", "free-space", "what-is-system-data"}) do
	t.expect(Guide.topic(id) ~= nil, "the guide explains " .. id)
end
t.assertEqual(Guide.measurement(model, Guide.topic("derived-data")), "4.9 GB on this Mac", "topics show live sizes")
t.assertEqual(Guide.measurement(model, Guide.topic("container")), nil, "topics without resources show no size")
t.assertEqual(Guide.measurement(model, Guide.topic("preboot")), nil, "unmeasured topics never show zero")
local swap = Guide.presentation(model, "SWAP")
t.expect(swap.count >= 1 and swap.count < topics, "guide search is case-insensitive and narrows topics")
t.expect(Guide.presentation(model, "no topic mentions this").empty, "guide search can be empty")
local chapter = Guide.presentation(model, "recovery and updates").chapters
t.assertEqual(#chapter, 1, "a chapter title match keeps its chapter")
t.assertEqual(#chapter[1].topics, #Guide.chapters[2].topics, "a matching chapter keeps all of its topics")
model.measurements.preboot = {status = "calculating"}
t.assertEqual(Guide.measurement(model, Guide.topic("preboot")), "Measuring…", "topics show measurement progress")

os.exit(t.summary() and 0 or 1)
