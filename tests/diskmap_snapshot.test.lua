_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Snapshot = require("apps.diskmap.models.Snapshot")
local SnapshotComparison = require("apps.diskmap.services.SnapshotComparison")
local Scanner = require("apps.diskmap.services.Scanner")

local root = os.tmpname(); os.remove(root); os.execute("mkdir -p '" .. root .. "'")

-- The creation time comes from the uncompressed header alone.
local snapshotPath = root .. "/previous.bin"
Scanner.writeSnapshot(snapshotPath, {capacityBytes = 500e9, availableBytes = 100e9, createdAt = 1790000000},
	{{path = "/Users/test/Library/Developer/Xcode/DerivedData/App/Build", allocatedBytes = 2e9}})
t.assertEqual(Snapshot.created(snapshotPath), 1790000000, "the snapshot date reads from its header")
t.assertEqual(Snapshot.created(root .. "/missing.bin"), nil, "a missing snapshot has no date")
local junk = io.open(root .. "/junk.bin", "wb"); junk:write(string.rep("x", 100)); junk:close()
t.assertEqual(Snapshot.created(root .. "/junk.bin"), nil, "a file that is not a snapshot has no date")

-- Totals and changes per location.
local model = Model.new("/Users/test")
local function measure(values)
	model.measurements = {}
	for id, value in pairs(values) do
		model.measurements[id] = type(value) == "table" and value or {bytes = value, status = "complete"}
	end
end
measure({derived = 6e9, simulators = 11e9, downloads = 20e9, ["codex-cache"] = {status = "denied"}})
local totals = Snapshot.totals(model)
t.assertEqual(totals.derived, 6e9, "measured locations are totalled")
t.assertEqual(totals["codex-cache"], nil, "denied locations are left out")

local baseline = {createdAt = os.time({year = 2026, month = 9, day = 25, hour = 12}),
	totals = {derived = 2e9, simulators = 12e9, downloads = 20.01e9, ["codex-cache"] = 5e9, removed = 1e9}}
local decoded = Snapshot.decode(Snapshot.encode(baseline))
t.assertEqual(decoded.createdAt, baseline.createdAt, "the cached baseline keeps the snapshot date")
t.assertEqual(decoded.totals.simulators, 12e9, "the cached baseline round-trips")
t.assertEqual(Snapshot.decode("not a baseline"), nil, "an unreadable cache is ignored")

local changes = Snapshot.changes(model, baseline)
t.assertEqual(#changes.rows, 2, "only locations measured on both sides and changed by 50 MB or more are listed")
t.assertEqual(changes.rows[1].id, "derived", "the largest change comes first")
t.assertEqual(changes.rows[1].text, "+4.0 GB", "growth is signed")
t.assertEqual(changes.rows[2].text, "−1.0 GB", "shrinkage is signed")
t.expect(changes.rows[1].grew and not changes.rows[2].grew, "rows say which way they changed")
t.assertEqual(changes.rows[1].levelColor, "systemOrange", "growth bars are orange")
t.assertEqual(changes.rows[2].levelColor, "systemGreen", "freed-space bars are green")
t.assertEqual(changes.rows[2].relative, 0.25, "bars compare changes with the largest one")
t.expect(changes.rows[1].subtitle:find("Xcode", 1, true) ~= nil, "rows say where the location lives")
t.assertEqual(changes.since, "Sep 25", "changes name the snapshot date")
t.expect(changes.detail:find("4.0 GB more", 1, true) and changes.detail:find("1.0 GB freed", 1, true), "the summary totals growth and freed space")
t.expect(Snapshot.changes(model, nil) == nil, "no baseline has no changes")
measure({derived = 2e9})
local quiet = Snapshot.changes(model, baseline)
t.assertEqual(#quiet.rows, 0, "an unchanged Mac has no rows")
t.expect(quiet.detail:find("No location changed", 1, true) ~= nil, "and says so")
t.assertEqual(Snapshot.overview(quiet), nil, "the overview hides an empty comparison")

-- The overview shows the first rows and offers the rest.
local many = {createdAt = baseline.createdAt, totals = {}}
local values = {}
for index, id in ipairs({"derived", "simulators", "downloads", "archives", "devices", "documentation"}) do
	many.totals[id] = 1e9
	values[id] = 1e9 + index * 1e8
end
measure(values)
local overview = Snapshot.overview(Snapshot.changes(model, many))
t.assertEqual(#overview.rows, Snapshot.overviewLimit, "the overview shows the largest changes")
t.expect(overview.all, "and offers every change when there are more")
t.assertEqual(overview.since, "the Sep 25 snapshot", "reminders can name the snapshot")

-- The controller measures a snapshot once, caches the totals and compares.
measure({derived = 6e9, simulators = 11e9})
local stored
local service = {loadSnapshotSummary = function() return stored or "" end, saveSnapshotSummary = function(text) stored = text; return true end}
local measured, reported = 0, nil
local function controller(options)
	options.measure = options.measure or function(path, live)
		measured = measured + 1
		t.assertEqual(path, snapshotPath, "the saved snapshot is measured")
		t.assertEqual(live, model, "with the live model's catalog")
		return {derived = 2e9, simulators = 12e9}, Snapshot.created(path)
	end
	options.async = function(fn) fn() end
	options.changed = function(value) reported = value end
	return SnapshotComparison.new(model, service, options)
end
local first = controller({path = snapshotPath})
first:compare()
t.assertEqual(measured, 1, "a new snapshot is measured once")
t.assertEqual(reported and reported.rows[1].id, "derived", "changes are reported after measuring")
t.assertEqual(Snapshot.decode(stored).createdAt, 1790000000, "the baseline is cached against the snapshot date")
first:compare()
t.assertEqual(measured, 1, "later scans reuse the measured baseline")
local relaunched = controller({path = snapshotPath})
relaunched:compare()
t.assertEqual(measured, 1, "a relaunch reuses the cached baseline")
t.assertEqual(reported.rows[2].text, "−1.0 GB", "and reports the same changes")
Scanner.writeSnapshot(snapshotPath, {capacityBytes = 500e9, availableBytes = 100e9, createdAt = 1790500000},
	{{path = "/Users/test/Library/Developer/Xcode/DerivedData/App/Build", allocatedBytes = 2e9}})
relaunched:compare()
t.assertEqual(measured, 2, "a newer snapshot is measured again")
local oneOff = controller({path = snapshotPath, cache = false})
stored = nil
oneOff:compare()
t.assertEqual(stored, nil, "a one-off comparison leaves the saved baseline alone")
local failing = controller({path = snapshotPath, cache = false, measure = function() error("decode failed") end})
local failure
failing.changed = function(value, message) reported, failure = value, message end
failing:compare()
t.expect(reported == nil and failure:find("decode failed", 1, true), "a failed measurement reports its reason")
os.remove(snapshotPath)
local absent = controller({path = snapshotPath})
reported = "untouched"
absent:compare()
t.assertEqual(reported, "untouched", "without a snapshot nothing is compared")

-- The real measurement: a Mock HDD snapshot measured with the live catalog.
Scanner.writeSnapshot(snapshotPath, {capacityBytes = 500e9, availableBytes = 100e9, createdAt = 1790000000},
	{{path = root .. "/home/Library/Developer/Xcode/DerivedData/App/Build/big", allocatedBytes = 3e9}})
local live = Model.new(root .. "/home")
live.measurements = {derived = {bytes = 5e9, status = "complete"}}
local yields = 0
local real = SnapshotComparison.new(live, {}, {path = snapshotPath, cache = false,
	async = function(fn) fn() end, yield = function() yields = yields + 1 end,
	changed = function(value) reported = value end})
real:compare()
t.expect(reported ~= nil and reported.rows[1].id == "derived", "the snapshot is measured through Mock HDD with the live catalog")
t.assertEqual(reported and reported.rows[1].text, "+2.0 GB", "and compared per location")
t.assertEqual(reported and reported.rows[1].before, "3.0 GB", "rows keep the earlier size")

-- A discovered app is measured on both sides, so the residual "Other files"
-- row that no longer contains it does not read as shrinkage.
local appHome = root .. "/apps-home"
Scanner.writeSnapshot(snapshotPath, {capacityBytes = 500e9, availableBytes = 100e9, createdAt = 1790000000},
	{{path = "/Applications/Editor.app/Contents/MacOS/Editor", allocatedBytes = 4e9},
	 {path = "/Applications/Loose/file", allocatedBytes = 1e9}})
local withApp = Model.new(appHome)
t.expect(withApp.resources:add("apps-system", {id = "discovered-editor", name = "Editor.app", subtitle = "Installed application",
	path = "/Applications/Editor.app", action = "finder", policy = "Review"}) ~= nil, "the live scan discovers an app")
t.assertEqual(#withApp.resources:added(), 1, "the model remembers discovered locations")
local plain = SnapshotComparison.new(withApp, {}, {path = snapshotPath, cache = false, async = function(fn) fn() end,
	yield = function() end, changed = function() end})
local baselineTotals = select(1, plain.measure(snapshotPath, withApp, function() end))
t.assertEqual(baselineTotals["discovered-editor"], 4e9, "the snapshot measures the discovered app as its own location")
t.assertEqual(baselineTotals["apps-system-other"], 1e9, "and the residual row without it")

-- Views: the overview section offers Show All; the sheet lists every change.
local ns = require("AppKit")
local xml = require("ui.xml")
local shown = 0
local _, sectionRefs = xml.renderFile("apps/diskmap/views/Changes.etlua", {changes = overview, actions = {showAllChanges = function() shown = shown + 1 end}}, ns)
t.expect(sectionRefs.showAllChanges ~= nil, "a long comparison offers Show All")
-- The changed locations share one box, split by vertical separators.
local changesRow = sectionRefs.changesBox.contentView.subviews[1]
local dividers, items = 0, 0
for _, child in ipairs(changesRow.subviews) do
	if child.className == "NSBox" then dividers = dividers + 1 else items = items + 1 end
end
t.assertEqual(items, #overview.rows, "one item per changed location in a single box")
t.assertEqual(dividers, #overview.rows - 1, "with a vertical separator between neighbours")
local _, historyRefs = xml.renderFile("apps/diskmap/views/Changes.etlua", {changes = {rows = overview.rows, detail = "Since Sep 20 · 3 scans recorded"}, actions = {}}, ns)
t.expect(historyRefs.changesSection ~= nil and historyRefs.showAllChanges == nil, "history changes show without Show All")
local full = Snapshot.changes(model, many)
local _, sheetRefs = xml.renderFile("apps/diskmap/views/SnapshotChanges.etlua", {title = full.title, detail = full.detail,
	actions = {done = function() end, rowMenu = function() return {} end, reveal = function() end}}, ns)
sheetRefs.changes:replaceRows(full.rows)
t.assertEqual(sheetRefs.changes.rowCount, #full.rows, "the sheet lists every changed location")

os.execute("rm -rf '" .. root .. "'")

os.exit(t.summary() and 0 or 1)
