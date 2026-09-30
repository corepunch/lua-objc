_G.__headless = true
-- The macOS file system map (knowledge/Filesystem): its integrity, how the
-- scan uses it, what the Overview says about what it could not measure,
-- and the macOS Folders page built from it.
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Map = require("apps.diskmap.knowledge.Filesystem")
local Filesystem = require("apps.diskmap.models.Filesystem")
local Inventory = require("apps.diskmap.models.Inventory")
local Categories = require("apps.diskmap.models.Categories")
local Overview = require("apps.diskmap.models.Overview")
local Volumes = require("apps.diskmap.models.Volumes")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local home = "/Users/test"

-- Integrity: every location is named, explained and correctly linked.
local model = Model.new(home)
local seenPaths, seenLeftovers, count = {}, {}, 0
for _, area in ipairs(Map.areas) do
	t.expect(area.title ~= "" and area.summary ~= "" and #area.locations > 0, "an area is titled, explained and not empty: " .. area.id)
	for _, location in ipairs(area.locations) do
		count = count + 1
		t.expect(not seenPaths[location.path], "a location appears once: " .. location.path)
		seenPaths[location.path] = true
		t.expect(location.name ~= "" and #location.what > 20, "a location is named and explained: " .. location.path)
		t.expect(location.guard == nil or Map.guards[location.guard] ~= nil, "a guard is one the map explains: " .. location.path)
		if location.resource then
			t.expect(model.resources:find(location.resource) ~= nil, "a linked resource exists in the catalog: " .. location.resource)
		end
		if location.leftover then
			t.expect(not seenLeftovers[location.leftover.id], "a leftover id is unique: " .. location.leftover.id)
			seenLeftovers[location.leftover.id] = true
			local resource = model.resources:find(location.leftover.id)
			t.expect(resource ~= nil and resource.path == location.path, "a leftover becomes a catalog resource at its path: " .. location.leftover.id)
			t.expect(resource.reviewThreshold == location.leftover.threshold and resource.consequence == location.leftover.advice,
				"and Clean Up reviews it past its threshold with the map's advice")
		end
	end
end
t.expect(count >= 60, "the map covers the file system broadly")
local visual = Map.find("/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_Visual")
t.assertEqual(visual.guard, "sip", "the Apple Intelligence visual model is SIP protected")
t.assertEqual(Map.find("/private/var/db/com.apple.xpc.roleaccountd.staging").guard, "sip", "app install staging is SIP protected")
t.assertEqual(Map.find("/System/Volumes/Data/.DocumentRevisions-V100").guard, "owner", "document versions are readable only by macOS")
t.expect(Map.find("/macOS Install Data").leftover ~= nil, "an interrupted macOS install is a known leftover")
t.assertEqual(Map.leftover("install-data").path, "/macOS Install Data", "leftovers are found by id")
for _, location in ipairs(Map.protected()) do
	t.expect(location.guard == "sip" or location.guard == "owner", "only unreadable locations are skipped: " .. location.path)
end
for _, location in ipairs(Map.volumes()) do
	t.expect(Volumes.roles[location.volume] ~= nil, "a volume location names a known APFS role: " .. location.path)
end

-- The scan skips protected locations and sizes volumes by APFS.
local planModel = Model.new(home)
planModel.protected = {visual, Map.find("/private/var/db/oah")}
planModel.volumeUsage = {Preboot = 21e9, VM = 7e9, Recovery = 3e9}
local paths, ids, exclusions = Inventory.plan(planModel)
local planned, excluded = {}, {}
for _, path in ipairs(paths) do planned[path] = true end
for _, path in ipairs(exclusions) do excluded[path] = true end
t.expect(not planned[visual.path], "a protected resource is not walked")
t.expect(excluded[visual.path] and excluded["/private/var/db/oah"], "and no parent walk enters a protected location")
t.expect(planned["/System/Library/AssetsV2/com_apple_MobileAsset_UAF_SummarizationKitConfiguration"], "readable siblings are still measured")
t.expect(not planned["/System/Volumes/Preboot"] and not planned["/System/Volumes/VM"], "volumes with an APFS size are not walked")
t.assertEqual(planModel.measurements.preboot.bytes, 21e9, "Preboot takes its volume's used space")
t.assertEqual(planModel.measurements.vm.status, "complete", "swap is measured on the VM volume")
t.expect(planned["/System/Volumes/Update"], "a volume APFS did not report is walked instead")
local visualId
for _, row in ipairs(planModel.resources:leaves()) do if row.path == visual.path then visualId = row.id end end
t.assertEqual(planModel.measurements[visualId].status, "protected", "a protected resource reads as protected")
t.assertEqual(Model.sizeLabel({}, "protected").size, "Protected", "not No access")
Inventory.begin(planModel, ids)
t.assertEqual(planModel.measurements[visualId].status, "protected", "a refresh keeps a protected resource out of Calculating")
t.assertEqual(planModel.measurements.preboot.bytes, 21e9, "and keeps a volume's size")
Inventory.apply(planModel, ids, {trees = {}, rootStates = {}})
t.assertEqual(Categories.row(planModel, visualId).status, "protected", "the category tree carries the state")

-- APFS roles add up within the startup container only.
local list = {Containers = {
	{ContainerReference = "disk1", Volumes = {{Roles = {"Preboot"}, CapacityInUse = 6e6}}},
	{ContainerReference = "disk3", Volumes = {{Roles = {"Preboot"}, CapacityInUse = 21e9}, {Roles = {"VM"}, CapacityInUse = 7e9},
		{Roles = {}, CapacityInUse = 1e9}, {Roles = {"Data"}, CapacityInUse = 186e9}}},
}}
local usage = Volumes.usage(list, "disk3")
t.assertEqual(usage.Preboot, 21e9, "another container's Preboot is not counted")
t.assertEqual(usage.Data, 186e9, "every role of the startup container is read")
t.assertEqual(Volumes.usage(list, "disk9"), nil, "an unknown container has no usage")
t.assertEqual(Volumes.usage(nil, "disk3"), nil, "an unreadable list has no usage")

-- Refusals: known protected, scanner-flagged, and, with Full Disk Access
-- on, every remaining one. Only the rest are offered to Full Disk Access.
model.scan = {errors = 5, protected = 3, issues = {
	{path = "/System/Library/AssetsV2/com_apple_MobileAsset_Unknown", protected = true},
	{path = home .. "/Library/Mail"},
	{path = "/private/var/db/unknown", protected = true},
}}
model.protected = {visual, Map.find("/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_CodeLM"), Map.find("/private/var/db/oah")}
local privacy = Overview.unreadable(model)
t.assertEqual(#privacy.paths, 1, "the access request lists only folders permission can open")
t.assertEqual(privacy.total, 2, "and counts only those")
local protected = Overview.protected(model, false)
t.assertEqual(protected.count, 6, "known protected locations and refused ones count together")
t.assertEqual(table.concat(protected.names, ", "), "Apple Intelligence models, Rosetta translations", "locations serving one feature are named once")
t.assertEqual(Overview.protected(model, true).count, 8, "with Full Disk Access on, every refusal is one no permission lifts")
local disk = {totalKb = 200e9 / 1024, freeKb = 20e9 / 1024}
local split = {}
for _, row in ipairs(Overview.hidden(disk, nil, 0, 5, 0, 0, false, protected)) do split[row.id] = row end
t.assertEqual(split.unreadable.value, "2", "unreadable locations leave out protected folders")
t.assertEqual(split.protected.value, "6", "protected folders have their own row")
local granted = {}
for _, row in ipairs(Overview.hidden(disk, nil, 0, 5, 0, 0, false, Overview.protected(model, true))) do granted[row.id] = row end
t.expect(granted.unreadable == nil, "with Full Disk Access on, nothing is offered to it")

-- The card says how much is in no category and why.
local card = Overview.unmeasured(model, disk, {fullDiskAccess = false, snapshotCount = 3, mediaExcluded = true})
local items = {}
for _, item in ipairs(card.items) do items[item.id] = item end
t.expect(items.protected.detail:find("Including Apple Intelligence models, Rosetta translations", 1, true) == 1, "protected locations are named")
t.assertEqual(items.protected.value, "6 locations", "and counted")
t.expect(items.privacy.grant and #items.privacy.paths == 1, "folders Full Disk Access would open offer it")
t.assertEqual(items.snapshots.value, "3", "snapshots are counted")
t.assertEqual(items.media.value, "Not scanned", "excluded media libraries are named")
t.expect(card.summary:find("180.0 GB of used space is in no category", 1, true) == 1, "the residual is stated up front")
local grantedCard = Overview.unmeasured(model, disk, {fullDiskAccess = true})
t.assertEqual(#grantedCard.items, 1, "with access granted, only protected locations remain")
model.protected, model.scan = nil, {}
t.assertEqual(#Overview.unmeasured(model, disk, {fullDiskAccess = true}).items, 0, "nothing unmeasured, nothing listed")

-- The macOS Folders page: every location, with the right state.
local page = Model.new(home)
page.volumeUsage = {Preboot = 21e9}
page.measurements.preboot = {bytes = 21e9, status = "complete"}
local pending = Filesystem.pending(page)
local pendingSet = {}
for _, path in ipairs(pending) do pendingSet[path] = true end
t.expect(pendingSet["/cores"] == nil, "a leftover with a resource is not measured twice")
t.expect(pendingSet["/Users/Shared"], "a location no resource covers is measured by the page")
t.expect(not pendingSet[visual.path], "a protected location is never measured")
local sizes = {["/Users/Shared"] = {bytes = 5e8, state = "measured"},
	["/System/Volumes/Data/.PreviousSystemInformation"] = {bytes = 0, state = "missing"},
	["/Library/Trial"] = {bytes = 0, state = "unreadable"}}
local presentation = Filesystem.presentation(page, sizes, false)
local rows = {}
for _, area in ipairs(presentation.areas) do for _, row in ipairs(area.rows) do rows[row.id] = row end end
t.assertEqual(presentation.count, count, "the page lists every location")
t.assertEqual(rows["/System/Volumes/Preboot"].size, "21.0 GB", "a volume shows its APFS size")
t.assertEqual(rows["/Users/Shared"].size, "500.0 MB", "a measured location shows its size")
t.assertEqual(rows[visual.path].size, "Not readable", "a protected location says it cannot be read")
t.assertEqual(rows[visual.path].guardTitle, Map.guards.sip.title, "and why")
t.assertEqual(rows["/System/Volumes/Data/.PreviousSystemInformation"].size, "Not on this Mac", "a missing location says so")
t.assertEqual(rows["/Library/Trial"].size, "No access", "a refused location asks for access while it is off")
local grantedRows = {}
for _, area in ipairs(Filesystem.presentation(page, sizes, true).areas) do for _, row in ipairs(area.rows) do grantedRows[row.id] = row end end
t.assertEqual(grantedRows["/Library/Trial"].size, "Not readable", "and is protected once access is on")
t.expect(rows["/System/Volumes/Data/MobileSoftwareUpdate"].calculating, "a leftover still measuring shows a spinner")
t.assertEqual(Filesystem.presentation(page, sizes, false, "rosetta").count, 1, "search finds a location by what it holds")
t.expect(Filesystem.presentation(page, sizes, false, "no such folder").empty, "a search with no match is empty")

-- A volume without an APFS size never spins forever: once APFS has
-- answered, a volume it did not report reads Not measured.
local volumeless = Model.new(home)
local function rowOf(m, id)
	for _, area in ipairs(Filesystem.presentation(m, {}, false).areas) do
		for _, row in ipairs(area.rows) do if row.id == id then return row end end
	end
end
t.expect(rowOf(volumeless, "/").calculating, "the system volume waits while APFS has not answered")
volumeless.volumeUsage = {}
t.assertEqual(rowOf(volumeless, "/").size, "Not measured", "and says so once APFS could not size it")

-- Volume sizes are asked for when a scan starts, not after discovery.
local Scan = require("apps.diskmap.controllers.ScanController")
local asked, discovering = false, nil
local service = {
	apfsVolumes = function(completion) asked = true; completion(list, "disk3") end,
	discoverEntries = function(_, completion) discovering = completion end,
	start = function() return {} end, await = function() end, cancel = function() end,
}
local scanModel = Model.new(home)
local scan = Scan.new(scanModel, service, home)
scan:start()
t.expect(asked and discovering ~= nil, "APFS is asked while discovery is still running")
t.assertEqual(scanModel.volumeUsage.Preboot, 21e9, "so volume sizes are known before the walk")

-- The page opens from the sidebar and the Overview card, and renders.
local app = Controller.new(Mock.new())
app:createWindow()
app:show("overview")
t.expect(app.pages.overview.notMeasured.refs.exploreFolders ~= nil, "the card links to macOS Folders")
app.pages.overview.handlers.navigate("filesystem")
t.assertEqual(app.destination, "filesystem", "which opens the page")
t.expect(app.pages.filesystem.refs.area_volumes ~= nil and app.pages.filesystem.refs.area_home ~= nil, "every area is on the page")
t.expect(app.model.folderSizes ~= nil, "the page measures the locations no resource covers")
app.scan:start()
t.expect(app.model.folderSizes == nil or app.model.scan.completedAt ~= nil, "a new scan discards the page's sizes")

os.exit(t.summary() and 0 or 1)
