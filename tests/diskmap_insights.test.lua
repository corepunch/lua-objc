_G.__headless = true
-- Large Files, File Types, Applications, Clean Up and Disks against the
-- synthetic Mock HDD, plus the pure rules behind them.
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Model = require("apps.diskmap.Model")
local Mock = require("apps.diskmap.services.Mock")
local Files = require("apps.diskmap.models.Files")
local Applications = require("apps.diskmap.models.Applications")
local Volumes = require("apps.diskmap.models.Volumes")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Inventory = require("apps.diskmap.models.Inventory")
local Controller = require("apps.diskmap.Controller")
local home = os.getenv("HOME")

-- The mock scan honours the same summary options as the native scanner.
local service = Mock.new()
local now = os.time()
local roots = {home .. "/Downloads", home .. "/Library/Containers"}
local summary = service.scan(roots, {home .. "/Library/Containers/com.apple.mail"}, {files = 3, minimumFileBytes = 1e9,
	oldBefore = now - 365 * 86400, extensions = true, breakdown = true})
t.assertEqual(#summary.largeFiles, 3, "the mock ranks at most the requested files")
t.assertEqual(summary.largeFiles[1].path, home .. "/Downloads/Old macOS Installer.dmg", "the mock ranks files largest first")
t.expect(summary.largeFiles[1].used < now - 500 * 86400, "profile ages date the mock files")
for _, file in ipairs(summary.largeFiles) do t.expect(file.bytes >= 1e9, "files below the minimum are not ranked") end
local oldPaths = {}
for _, file in ipairs(summary.oldFiles) do oldPaths[file.path] = true end
t.expect(oldPaths[home .. "/Downloads/ubuntu-24.04-desktop-arm64.iso"], "unused files are ranked separately")
t.expect(not oldPaths[home .. "/Library/Containers/com.mock.VideoStudio/Data/Library/Caches/render.cache"], "recent files are not old")
local extensions = {}
for _, row in ipairs(summary.extensions) do extensions[row.extension] = row end
t.expect(extensions.dmg and extensions.iso and extensions.pkg, "the mock totals extensions")
local containers = {}
for _, child in ipairs(summary.breakdowns[2]) do containers[child.name] = child end
t.expect(containers["com.mock.RemovedEditor"] and containers["com.mock.RemovedEditor"].directory, "breakdowns list immediate child folders")
t.expect(containers["com.apple.mail"] == nil, "excluded locations stay out of breakdowns")

-- File kinds and ages.
t.assertEqual(Files.kind("/x/Movie.MOV").id, "video", "kinds ignore extension case")
t.assertEqual(Files.kind("/x/archive.tar.gz").id, "archives", "the last extension decides the kind")
t.assertEqual(Files.kind("/x/.hidden").id, "other", "dot files have no kind")
t.assertEqual(Files.age(now - 3 * 86400, now), "3 days ago", "recent ages are in days")
t.assertEqual(Files.age(now - 400 * 86400, now), "1 year ago", "old ages are in years")
t.assertEqual(Files.age(nil, now), "Unknown", "missing dates are unknown, not zero")
t.assertEqual(Model.count(1234567), "1,234,567", "counts use thousands separators")
t.assertEqual(Model.count(12), "12", "short counts are unchanged")

-- A full mock launch fills every summary.
local app = Controller.new(Mock.new())
app.scan:start()
local model = app.model
t.expect(model.files ~= nil and #model.files.large > 0, "a finished scan keeps the large-file ranking")
t.expect(model.breakdowns["app-containers"] ~= nil, "a finished scan keeps per-location breakdowns")

-- Trash eligibility for individual files.
local function reason(path) local _, err = Files.validateTrash(model, path); return err and err.code end
t.expect(Files.validateTrash(model, home .. "/Downloads/Old macOS Installer.dmg"), "ordinary downloads can be moved to the Trash")
t.assertEqual(reason(home .. "/Library/Application Support/MobileSync/Backup/mock-phone/Manifest.db"), "library", "Library files belong to apps")
t.assertEqual(reason(home .. "/.ollama/models/blobs/sha256-6a0746a1ec1a"), "hidden", "hidden tool folders are not trashed file by file")
t.assertEqual(reason(home .. "/Pictures/Mock Photos.photoslibrary/originals/image.heic"), "package", "files inside packages belong to their app")
t.assertEqual(reason("/Applications/Mock Notes.app"), "outside_home", "files outside the home folder are never trashed here")
t.assertEqual(reason(home .. "/Downloads/never-measured.dmg"), "not_measured", "only measured files can be trashed")
t.assertEqual(reason(home .. "/Downloads/../.ssh/id"), "invalid_path", "relative components are refused")
model.kept.downloads = true
t.assertEqual(reason(home .. "/Downloads/Old macOS Installer.dmg"), "kept", "a kept location protects its files")
model.kept.downloads = nil

-- Large Files filters.
local all = Files.rows(model, "All")
t.expect(#all > 5, "large files are listed")
for index = 2, #all do t.expect(all[index - 1].bytes >= all[index].bytes, "large files are largest first") end
t.assertEqual(all[1].relative, 1, "the largest file has a full bar")
for _, row in ipairs(Files.rows(model, "Unused for a year")) do t.expect(row.old, "the unused filter lists only old files") end
for _, row in ipairs(Files.rows(model, "Installers & archives")) do
	t.expect(row.kindId == "installers" or row.kindId == "archives", "the installer filter lists installers and archives")
end
for _, row in ipairs(Files.rows(model, "All", nil, "video")) do t.assertEqual(row.kindId, "video", "a kind narrows the list") end
t.assertEqual(#Files.rows(model, "All", "ubuntu"), 1, "search matches file names")
local fileSummary = Files.summary(model)
t.expect(fileSummary.reviewableOldBytes > 0 and fileSummary.reviewableOldBytes <= fileSummary.oldBytes, "reviewable old files are a subset of old files")

-- File Types.
local kinds, top = Files.kinds(model)
t.expect(#kinds > 3 and #top > 3, "file types group extensions into kinds")
local share = 0
for _, kind in ipairs(kinds) do share = share + kind.share end
t.expect(math.abs(share - 1) < 1e-9, "kind shares add up to all measured files")
t.assertEqual(kinds[1].relative, 1, "the largest kind has a full bar")

-- Applications, their data and leftovers.
local info
app.service.applicationInfo({"/Applications/Mock Video Studio.app", "/Applications/Mock Notes.app", home .. "/Applications/Mock Game.app"}, function(value) info = value end)
local apps = Applications.rows(model, info, "All")
local byName = {}
for _, row in ipairs(apps) do byName[row.name] = row end
t.expect(byName["Mock Video Studio"] and byName["Mock Video Studio"].dataBytes == 2.2e9, "app data is found by bundle identifier")
t.assertEqual(byName["Mock Video Studio"].bytes, 3.4e9 + 2.2e9, "an app's total includes its data")
t.expect(byName["Mock Game"].unused and not byName["Mock Notes"].unused, "apps unused for six months are flagged")
t.expect(byName["Xcode & bundled SDKs"] == nil, "missing bundles are not listed as installed")
local unused = Applications.rows(model, info, "Unused for 6 months")
t.assertEqual(#unused, 1, "the unused filter lists only unused apps")
t.assertEqual(Applications.leftovers(model, nil), nil, "without installed identifiers nothing is called a leftover")
local installed
app.service.installedBundleIds(function(ids) installed = ids end)
local leftovers = Applications.leftovers(model, installed)
local leftoverNames = {}
for _, row in ipairs(leftovers) do leftoverNames[row.name] = row end
t.expect(leftoverNames["com.mock.RemovedEditor"] and leftoverNames["com.mock.OldGame"], "unclaimed identifier folders are leftovers")
t.expect(leftoverNames["com.mock.VideoStudio"] == nil, "installed apps' data is never a leftover")
table.insert(installed, "com.mock.RemovedEditor.helper")
t.expect(not Applications.validateLeftover(model, installed, home .. "/Library/Containers/com.mock.RemovedEditor"), "a helper identifier claims its host's data")
table.remove(installed)
t.expect(Applications.validateLeftover(model, installed, home .. "/Library/Containers/com.mock.RemovedEditor"), "an unclaimed folder can be reviewed")
local parsed = Applications.parseLastUsed("2026-09-20 16:20:00 +0000\0(null)\0" .. "2026-01-01 00:00:00 -0500", {"/A.app", "/B.app", "/C.app"})
t.assertEqual(parsed["/A.app"], 1789921200, "Spotlight dates parse as UTC")
t.assertEqual(parsed["/B.app"], nil, "never-opened apps have no date")
t.assertEqual(parsed["/C.app"], 1767243600, "time zone offsets are applied")

-- Disks & Volumes.
local volumes
app.service.volumes(function(value) volumes = value end)
local health = Volumes.health(volumes.info)
local facts = {}
for _, fact in ipairs(health) do facts[fact.id] = fact end
t.assertEqual(facts.smart.value, "Verified", "SMART status is reported")
t.assertEqual(facts.encryption.value, "FileVault on", "FileVault is reported")
t.assertEqual(#Volumes.health(nil), 0, "unknown disks report no invented facts")
local apfs = Volumes.apfs(volumes.apfs, "disk3")
t.assertEqual(#apfs.rows, 6, "every APFS volume is listed")
t.assertEqual(apfs.rows[1].name, "Data", "volumes are largest first")
local used = 0
for _, row in ipairs(apfs.rows) do used = used + row.bytes end
t.assertEqual(used + apfs.free, apfs.capacity, "mock volumes and free space partition the container")
t.assertEqual(#Volumes.external(volumes.external), 1, "other mounted disks are listed")

-- Clean Up uses every knowledge entry.
local cleanup = Recommendations.presentation(model, nil, app.pages.applications:summary())
t.expect(#cleanup.rebuildable > 0 and #cleanup.review > 0, "clean up separates rebuildable and review suggestions")
local rebuildable = {}
for _, row in ipairs(cleanup.rebuildable) do rebuildable[row.id] = true end
t.expect(rebuildable["iphone-updates"] and rebuildable["sim-caches"] and rebuildable.playwright, "new knowledge entries become suggestions")
local elsewhere = {}
for _, row in ipairs(cleanup.elsewhere) do elsewhere[row.id] = row end
t.expect(elsewhere["old-files"] and elsewhere.installers, "clean up points to files worth reviewing")
t.expect(cleanup.known > #cleanup.rebuildable + #cleanup.review, "every rule and threshold is on the checklist")
t.expect(cleanup.absent > 0, "knowledge entries absent from this Mac are counted")

-- Row menus: resources, files and folders share one vocabulary.
local titles = function(items)
	local result = {}
	for _, item in ipairs(items) do if item.title then result[item.title] = item end end
	return result
end
local derivedMenu = titles(app.actions:resource("derived"))
t.expect(derivedMenu["Review Move to Trash…"] and derivedMenu["Show in Finder"] and derivedMenu.Keep and derivedMenu["Copy Path"], "resource menus offer review, Finder, Keep and Copy")
local dmg
for _, row in ipairs(Files.rows(model, "All")) do if row.name == "Old macOS Installer.dmg" then dmg = row end end
local fileMenu = app.actions:file(dmg)
t.assertEqual(fileMenu[1].title, "Move to Trash…", "own documents can be moved to the Trash from their menu")
local backup
for _, row in ipairs(Files.rows(model, "All")) do if row.name == "Manifest.db" then backup = row end end
local backupMenu = app.actions:file(backup)
t.expect(backupMenu[1].disabled and backupMenu[1].title:find("belong to apps", 1, true), "a refused trash explains itself in the menu")

-- Trashing a file from its menu moves it and remeasures.
local originalConfirm = app.service.confirmTrashPath
app.service.confirmTrashPath = function() return true end
local before = model.measurements.downloads.bytes
app.actions:trashFile(dmg)
t.expect(model.measurements.downloads.bytes < before, "moving a file to the Trash remeasures its location")
t.expect(model.measurements["user-trash"].bytes and model.measurements["user-trash"].bytes >= dmg.bytes, "the moved file is counted in the Trash")
app.service.confirmTrashPath = originalConfirm

-- Pages mount and fill their lists headlessly.
local window = app:createWindow()
for _, id in ipairs({"files", "kinds", "cleanup", "applications", "disks", "developer", "largest"}) do
	app:show(id)
	t.assertEqual(app.destination, id, "the " .. id .. " page mounts")
end
app:show("files")
t.expect(app.refs.files.rowCount > 0, "Large Files lists files")
app:show("kinds")
t.expect(app.refs.kinds.rowCount > 0 and app.refs.extensions.rowCount > 0, "File Types lists kinds and extensions")
app.pages.kinds.showFiles("installers")
t.assertEqual(app.destination, "files", "opening a kind shows Large Files")
t.expect(not app.refs.clearKind.hidden, "a narrowed list offers to show every kind")
for index = 1, app.refs.files.rowCount do
	t.assertEqual(bridge._tableCell(app.refs.files, 3, index - 1).textField.stringValue ~= nil, true, "file rows render")
end
app:show("applications")
t.expect(app.refs.apps.rowCount >= 3 and app.refs.leftovers.rowCount >= 2, "Applications lists apps and leftovers")
app:show("disks")
t.assertEqual(app.refs.volumes.rowCount, 6, "Disks lists the startup container's volumes")
window.size = ns.Size(880, 580); window:layout()
t.expect(app.refs.page.frame.size.width <= 880, "pages fit the minimum window")
window:close()
os.exit(t.summary() and 0 or 1)
