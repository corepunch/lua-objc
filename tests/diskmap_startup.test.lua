_G.__headless = true
local t = require("TestKit")
local Controller = require("apps.diskmap.Controller")
local bridge = require("AppKitNative")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local savedArgs = arg
local launches, monitors, capacityReads = 0, 0, 0
local service = require("apps.diskmap.services.Contract").stub({
	badge = false, label = false,
	start = function(paths)
		launches = launches + 1
		t.expect(#paths > 100, "launch inventories every catalog location")
		return {}
	end,
	await = function(job, completion) job.complete = completion end,
	cancel = function() end,
	diskSpace = function()
		capacityReads = capacityReads + 1
		return {totalKb = 1000000, freeKb = 500000}
	end,
	loadKeep = function() return {derived = true} end,
	loadSettings = function() return false end,
	monitor = function() monitors = monitors + 1 end,
})
-- Obsolete command-line arguments cannot bypass a fresh launch or enable disk IO.
setmetatable(service, {__index = function(_, key)
	error("Unexpected service call: " .. key)
end})
for i, arguments in ipairs({{}, {"-cache=/missing/inventory.json"},
	{"--cache=/missing/inventory.json"}, {"--write-cache=/missing/inventory.json"}}) do
	arg = arguments
	local app = Controller.new(service)
	local window = app:createWindow()
	t.assertEqual(launches, i, "each new app instance starts its own scan")
	t.assertEqual(monitors, i, "every launch installs background monitoring")
	t.assertEqual(Scans:measured(), 0, "new launch has no previous measurement values")
	t.expect(app.env.model.kept.derived, "Keep preferences survive independently of measurements")
	t.expect(not app.env.session.monitorEnabled and app.env.scan.job ~= nil, "paused background checks do not suppress startup scan")
	for _, row in ipairs(Categories:rows()) do
		t.expect(row.calculating or row.status == "excluded" or row.status == "unsupported", "startup recalculates allowed category: " .. row.id)
	end
	local _, ids = Scans:plan()
	local result = {trees = {}, rootStates = {}}
	for index, id in ipairs(ids) do
		result.rootStates[index] = id == "derived" and "measured" or "missing"
		if id == "derived" then result.trees[index] = {kb = i * 100} end
	end
	app.env.scan.job.complete(result)
	t.assertEqual(app.env.model.measurements.derived.bytes, i * 102400, "launch displays its own fresh result")
	t.assertEqual(app.env.scan.job, nil, "completed scan is released without saving an inventory")
	t.expect(dofile("tests/fixtures/meter.lua")(bridge._tableCell(app.page.refs.results, 1, 0)).spinner.hidden, "fresh completion stops row spinner")
	app.env.scan:dispose(); window:close()
end
t.assertEqual(capacityReads, 8, "capacity is queried at startup and completion for every launch")
arg = savedArgs
os.exit(t.summary() and 0 or 1)
