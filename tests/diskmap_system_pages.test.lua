_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Simulators = require("apps.diskmap.models.Simulators")
local Updates = require("apps.diskmap.models.Updates")

-- Simulator runtimes as `xcrun simctl runtime list -j` reports them.
local ios = "5B0E6C62-9E4B-4C57-9B63-2D5F3A4E7A11"
local watch = "E2F7B1C8-6A40-4D93-A5B2-1C9E8F3D6B70"
local list = {
	[ios] = {identifier = ios, runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
		platformIdentifier = "com.apple.platform.iphonesimulator", version = "26.0", build = "23A339",
		kind = "Disk Image", state = "Ready", deletable = true, sizeBytes = 8.42e9, lastUsedAt = "2026-09-20T16:20:00Z"},
	[watch] = {identifier = watch, runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.watchOS-26-0",
		platformIdentifier = "com.apple.platform.watchsimulator", version = "26.0", deletable = false},
	broken = "not a runtime",
}
local now = os.time({year = 2026, month = 9, day = 26, hour = 12})
local inventory = {runtimes = {}, devices = {
	["com.apple.CoreSimulator.SimRuntime.iOS-26-0"] = {
		{udid = "11111111-2222-4333-8444-555555555555", name = "iPhone 17 Pro", isAvailable = true, state = "Shutdown",
			lastUsedAt = "2026-09-20T16:20:00Z", dataPathSize = 8.8e9},
		{udid = "22222222-2222-4333-8444-555555555555", name = "iPhone 12", isAvailable = true, state = "Shutdown",
			lastUsedAt = "2025-01-10T08:00:00Z", dataPathSize = 3e9},
		{udid = "33333333-2222-4333-8444-555555555555", name = "iPad (never booted)", isAvailable = true, state = "Shutdown"},
	},
	["com.apple.CoreSimulator.SimRuntime.iOS-17-0"] = {
		{udid = "44444444-2222-4333-8444-555555555555", name = "Old iPhone", isAvailable = false, state = "Shutdown", dataPathSize = 1e9},
	},
}}

local runtimes = Simulators.runtimeRows(list, inventory)
t.assertEqual(#runtimes, 2, "malformed runtime entries are skipped")
t.assertEqual(runtimes[1].name, "iOS 26.0", "runtime names come from platform and version")
t.assertEqual(runtimes[1].subtitle, "Build 23A339 · Disk Image · Ready", "runtime details name build, kind and state")
t.assertEqual(runtimes[1].deviceText, "3 devices", "runtimes count the devices that use them")
t.assertEqual(runtimes[1].lastUse, "2026-09-20", "runtime last use is a date")
t.assertEqual(runtimes[2].name, "watchOS 26.0", "watch runtimes are named for their platform")
t.assertEqual(runtimes[2].size, "Not measured", "a runtime without a size is not zero")
t.assertEqual(runtimes[2].lastUse, "Not recorded", "unknown last use is never invented")
t.assertEqual(#Simulators.runtimeRows(nil, inventory), 0, "no runtime list shows no runtimes")
t.assertEqual(#Simulators.runtimeRows(list, inventory, "watch"), 1, "runtime search matches platform names")

t.assertEqual(Simulators.runtimeCommand(runtimes[1])[5], ios, "runtime deletion uses the exact image UUID")
t.assertEqual(table.concat(Simulators.runtimeCommand(runtimes[1]), " ", 1, 4), "/usr/bin/xcrun simctl runtime delete",
	"runtime deletion is simctl's own command")
local ok, err = Simulators.validateRuntime(runtimes[2])
t.expect(not ok and err.code == "not_deletable", "runtimes simctl will not delete stay in Xcode's hands")
t.expect(not Simulators.runtimeCommand({id = "all", deletable = true}), "wildcard runtime deletion is forbidden")
t.expect(not Simulators.runtimeCommand(nil), "no selection has no command")
local model = Model.new("/Users/test")
model.kept.xcode = true
t.expect(not Simulators.runtimeCommand(runtimes[1], model), "Keep on Xcode protects its runtimes")
model.kept.xcode = nil
t.expect(Simulators.runtimeImpact(runtimes[1]):find("3 devices using it will become unavailable", 1, true) ~= nil,
	"runtime confirmation names the devices it strands")

t.assertEqual(Simulators.age("2026-09-20T16:20:00Z", now), 6, "device age counts whole days")
t.assertEqual(Simulators.age(nil, now), nil, "missing dates have no age")
t.assertEqual(Simulators.age("yesterday", now), nil, "unreadable dates have no age")
local stale = Simulators.rows(inventory, nil, Simulators.filters[3], now)
t.assertEqual(#stale, 1, "only devices with a recorded, old last use are unused")
t.assertEqual(stale[1].name, "iPhone 12", "the stale filter finds the old device")
t.assertEqual(#Simulators.rows(inventory, nil, "Unavailable", now), 1, "the unavailable filter still works")
t.assertEqual(#Simulators.rows(inventory, nil, "All", now), 4, "all devices are listed")

local summary = Simulators.summary(inventory, runtimes, now)
t.assertEqual(summary.devices, 4, "summary counts every device")
t.assertEqual(summary.deviceBytes, 12.8e9, "unmeasured devices add no bytes")
t.assertEqual(summary.unavailable, 1, "summary counts unavailable devices")
t.assertEqual(summary.unavailableBytes, 1e9, "summary totals unavailable device data")
t.assertEqual(summary.stale, 1, "summary counts stale devices")
t.assertEqual(summary.runtimes, 2, "summary counts runtimes")
t.assertEqual(summary.runtimeBytes, 8.42e9, "unmeasured runtimes add no bytes")

-- Software Update's record.
local plist = {AutomaticDownload = true, LastSuccessfulDate = "2026-09-24 08:12:00 +0000",
	RecommendedUpdates = {{["Display Name"] = "macOS Tahoe 26.1", ["Display Version"] = "26.1"}}}
local update = Updates.softwareUpdate(plist)
t.assertEqual(update.title, "macOS Tahoe 26.1 is available", "a single update is named")
t.assertEqual(update.detail, "Last checked Sep 24, 2026 · Downloads automatically", "the record says when it was made")
plist.RecommendedUpdates[2] = {Identifier = "Safari"}
t.assertEqual(Updates.softwareUpdate(plist).title, "2 updates are available", "several updates are counted")
t.assertEqual(Updates.softwareUpdate({}).title, "No updates waiting", "an empty record has no updates")
t.assertEqual(Updates.softwareUpdate({}).detail, "Last check date unknown", "an unknown check date is said plainly")
t.expect(not Updates.softwareUpdate(nil).known, "an unreadable record is unknown, not up to date")
t.assertEqual(Updates.formatDate(0), "Jan 1, 1970", "numeric dates are formatted")

local snapshots = Updates.snapshots({"com.apple.TimeMachine.2026-09-22-184200.local", "com.apple.TimeMachine.20260926-101500.local"})
t.assertEqual(snapshots[1].name, "Sep 26, 2026 at 10:15", "the newest snapshot comes first")
t.assertEqual(snapshots[2].name, "Sep 22, 2026 at 18:42", "dashed snapshot identifiers are readable")

model.measurements["update-assets-2"] = {bytes = 12e9, status = "complete"}
model.measurements["update-volume"] = {bytes = 0, status = "complete"}
model.measurements.preboot = {status = "calculating"}
local installer = model.resources:add("apps-system", {id = "installer", name = "Install macOS Tahoe.app", subtitle = "Full macOS installer app",
	path = "/Applications/Install macOS Tahoe.app", policy = "Review", action = "finder"})
t.expect(installer ~= nil, "an installer can be registered")
model.measurements.installer = {bytes = 16e9, status = "complete"}
local page = Updates.presentation(model, plist, false)
t.assertEqual(page.stages[1].size, "≥ 12.0 GB", "downloaded updates show their measured size")
t.assertEqual(page.stages[2].size, "0 KB", "an empty Update volume is measured as empty")
t.assertEqual(page.stages[3].size, "Calculating…", "stages show measurement progress")
t.assertEqual(#page.installers, 1, "installers in Applications are found by name")
t.assertEqual(page.installers[1].name, "Install macOS Tahoe", "installer names drop the app extension")
t.assertEqual(page.installers[1].size, "16.0 GB", "installers show their size")
t.assertEqual(page.snapshotTitle, "Local snapshots could not be listed", "a failed tmutil call is reported")
t.assertEqual(Updates.presentation(model, plist, nil).snapshotTitle, "Checking local snapshots…", "pending snapshots say so")
t.assertEqual(Updates.presentation(model, plist, {}).snapshotTitle, "No local snapshots", "no snapshots is a result")
for _, stage in ipairs(Updates.stages) do
	t.expect(model.resources:find(stage.id) ~= nil, "update stage cites a registered resource: " .. stage.id)
end

os.exit(t.summary() and 0 or 1)
