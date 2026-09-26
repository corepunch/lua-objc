_G.__headless = true
local t = require("TestKit")
local Provider = require("apps.diskmap.services.Provider")
local Mock = require("apps.diskmap.services.Mock")
local Simulators = require("apps.diskmap.models.Simulators")

local home = "/Users/mock-diskmap"
local args = {[0] = "apps/diskmap/init.lua", [1] = "--mock"}
local selected = Provider.select(args)
t.expect(selected.mock, "--mock selects the virtual provider")
t.assertEqual(package.loaded["apps.diskmap.services.System"], nil, "mock selection does not load the real disk provider")
t.assertEqual(Provider.select({[1] = "-mock"}).mock, true, "single-dash mock spelling is accepted")
local fixturePath = "apps/diskmap/mock-hdd.bin"
t.assertEqual(Provider.select({[1] = "--mock-file=" .. fixturePath}).mock, true, "--mock-file loads a selected local snapshot")
t.assertEqual(Provider.exportPath({[1] = "--export-mock=/private/tmp/example.bin"}), "/private/tmp/example.bin", "export switch selects its local destination")
t.assertEqual(package.loaded["apps.diskmap.services.System"], nil, "loading a saved mock snapshot never loads the real provider")
local bundledFixture = assert(io.open(fixturePath, "rb"))
t.assertEqual(bundledFixture:read(8), "DMOCK001", "bundled Mock HDD fixture is binary")
bundledFixture:close()

local originalSnapshotPath = Provider.savedSnapshotPath
Provider.savedSnapshotPath = function() return fixturePath end
_G.__headless = false
local saved = Provider.select({[1] = "--mock"})
local savedDiscoveries
saved.discoverEntries(home, function(entries) savedDiscoveries = entries end)
t.expect(saved.mock, "a saved disk snapshot still uses the mock provider")
t.assertEqual(#savedDiscoveries, 0, "a saved disk snapshot does not invent synthetic apps")
_G.__headless = true
local headlessSaved = Provider.select({[1] = "--mock"})
local headlessDiscoveries
headlessSaved.discoverEntries(home, function(entries) headlessDiscoveries = entries end)
t.assertEqual(headlessDiscoveries[1].path, "/Applications/Mock Video Studio.app", "headless runs keep the synthetic fixture")
Provider.savedSnapshotPath = originalSnapshotPath

local mock = Mock.new({home = home})
local discoveries
mock.discoverEntries(home, function(entries) discoveries = entries end)
t.assertEqual(#discoveries, 5, "mock discovery comes from the bundled profile rather than host filesystem traversal")
t.assertEqual(discoveries[1].path, "/Applications/Mock Video Studio.app", "mock app paths remain virtual")
local initialFree = mock.availableBytes
local initialDocumentation = mock.scan({"~/Library/Developer/Shared/Documentation"}, {})
t.assertEqual(initialDocumentation.rootStates[1], "measured", "fixture locations appear as measured roots")
t.assertEqual(initialDocumentation.trees[1].kb * 1024, 1300000000, "fixture preserves allocated byte totals")

local progress, completed
local job = mock.start({"~/Downloads", "~/not-in-the-fixture"}, {})
mock.await(job, function(result) completed = result end, function(result) progress = result end)
t.assertEqual(progress.completed, 2, "mock scans publish progress through the provider interface")
t.assertEqual(completed.rootStates[2], "missing", "unlisted virtual paths are reported as missing")
t.assertEqual(mock.diskSpace(home).freeKb, initialFree / 1024, "mock capacity comes from the fixture")

local moved, moveError = mock.trash("~/Library/Developer/Shared/Documentation")
t.expect(moved, moveError or "mock Trash operation succeeds")
t.assertEqual(mock.scan({"~/Library/Developer/Shared/Documentation"}, {}).rootStates[1], "missing", "moving to Trash removes the virtual source")
t.assertEqual(mock.scan({"~/.Trash"}, {}).trees[1].kb * 1024, 3700000000, "mock Trash contains the original and moved entries")
t.assertEqual(mock.availableBytes, initialFree, "moving files to Trash does not claim free capacity")
mock.emptyTrash()
t.assertEqual(mock.scan({"~/.Trash"}, {}).rootStates[1], "missing", "emptying Mock Trash removes its entries")
t.assertEqual(mock.availableBytes, initialFree + 3700000000, "emptying Mock Trash updates virtual free capacity")

local fresh = Mock.new({home = home})
t.assertEqual(fresh.scan({"~/Library/Developer/Shared/Documentation"}, {}).trees[1].kb * 1024, 1300000000, "restarting the provider restores fixture entries")
t.assertEqual(fresh.availableBytes, initialFree, "restarting restores the fixture's free capacity")

local cleanupOK, cleanupMessage
fresh.runOwnerCleanup("npm-cache", home, function(ok, message) cleanupOK, cleanupMessage = ok, message end)
t.expect(cleanupOK, cleanupMessage or "mock package-manager cleanup succeeds")
t.assertEqual(fresh.scan({"~/.npm/_cacache"}, {}).rootStates[1], "missing", "owner cleanup only removes virtual cache entries")
t.assertEqual(fresh.availableBytes, initialFree + 1400000000, "owner cleanup updates virtual free capacity")

local listOK, simulatorJSON
fresh.command({"/usr/bin/xcrun", "simctl", "list", "--json"}, function(ok, output) listOK, simulatorJSON = ok, output end)
t.expect(listOK, "simulator inventory is provided from Mock HDD data")
local simulators = fresh.decode(simulatorJSON)
t.assertEqual(simulators.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"][1].dataPathSize, 8800000000, "simulator sizes come from virtual entries")
local discovered = Simulators.discover(fresh, home)
local discoveredRows = Simulators.rows(discovered)
t.assertEqual(#discoveredRows, 2, "mock review lists simulator folders without calling simctl")
t.assertEqual(discoveredRows[1].name, "iPhone 17 Pro", "bundled simulator metadata supplies the device name")
t.assertEqual(discoveredRows[1].bytes, 8800000000, "review size is the device folder total")
local erased
fresh.command({"/usr/bin/xcrun", "simctl", "erase", "11111111-2222-4333-8444-555555555555"}, function(ok) erased = ok end)
t.expect(erased, "simulator erase is simulated in memory")
fresh.command({"/usr/bin/xcrun", "simctl", "list", "--json"}, function(_, output) simulatorJSON = output end)
simulators = fresh.decode(simulatorJSON)
t.assertEqual(simulators.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"][1].dataPathSize, 0, "simulator erase clears only its virtual data")
local deleted
fresh.command({"/usr/bin/xcrun", "simctl", "delete", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"}, function(ok) deleted = ok end)
t.expect(deleted, "simulator delete is simulated in memory")
fresh.command({"/usr/bin/xcrun", "simctl", "list", "--json"}, function(_, output) simulatorJSON = output end)
simulators = fresh.decode(simulatorJSON)
t.assertEqual(#simulators.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"], 1, "mock simulator deletion removes only the selected virtual device")
local restarted = Mock.new({home = home})
restarted.command({"/usr/bin/xcrun", "simctl", "list", "--json"}, function(_, output) simulatorJSON = output end)
simulators = restarted.decode(simulatorJSON)
t.assertEqual(#simulators.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"], 2, "restarting restores deleted mock devices")

local blocked
local originalExecute = os.execute
os.execute = function() blocked = true; error("Mock HDD attempted a host command") end
fresh.trash("~/Library/Developer/Xcode/DerivedData")
fresh.emptyTrash()
fresh.runOwnerCleanup("pip-cache", home, function() end)
fresh.command({"/usr/bin/xcrun", "simctl", "list", "--json"}, function() end)
local refused
fresh.command({"/bin/rm", "-rf", "/"}, function(ok) refused = not ok end)
os.execute = originalExecute
t.expect(not blocked, "mock scan and mutations never launch host commands")
t.expect(refused, "mock provider rejects commands outside its simulator fixture API")

local originalArgs = rawget(_G, "arg")
_G.arg = args
local Controller = require("apps.diskmap.Controller")
local app = Controller.new()
_G.arg = originalArgs
t.expect(app.service.mock, "Diskmap chooses its provider from application arguments")
t.assertEqual(package.loaded["apps.diskmap.services.System"], nil, "constructing Mock Diskmap never loads the real scanner")
app.scan:start()
t.assertEqual(app.model.measurements.downloads.bytes, 9300000000, "Diskmap inventory scans the synthetic Downloads tree")
t.assertEqual(app.model.measurements["mock-video-studio"].bytes, 3400000000, "discovered applications are measured from the mock fixture")
t.assertEqual(app.model.measurements.simulators.bytes, 11200000000, "simulator allocation is measured without simctl")
local xml, ns = require("ui.xml"), require("AppKit")
local window = xml.renderFile("apps/diskmap/views/Window.etlua", {subtitle = "360 GB free of 1 TB", windowTitle = "Diskmap — Mock HDD", actions = {search = function() end}}, ns)
t.assertEqual(window.title, "Diskmap — Mock HDD", "the active provider is visible in the window title")

os.exit(t.summary() and 0 or 1)
