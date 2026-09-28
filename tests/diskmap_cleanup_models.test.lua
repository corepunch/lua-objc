_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Xcode = require("apps.diskmap.models.Xcode")
local Leftovers = require("apps.diskmap.models.Leftovers")
local Projects = require("apps.diskmap.models.Projects")
local Basket = require("apps.diskmap.models.Basket")
local OperationLog = require("apps.diskmap.models.OperationLog")
local History = require("apps.diskmap.models.History")
local MapTree = require("apps.diskmap.models.MapTree")
local Overview = require("apps.diskmap.models.Overview")
local Updates = require("apps.diskmap.models.Updates")

-- Xcode: device support by version, newest kept per platform.
local parsed = Xcode.parseSupport("iPhone15,2 17.2 (21C62)")
t.assertEqual(parsed.version, "17.2", "Xcode 15 device support names carry the OS version")
t.assertEqual(parsed.model, "iPhone15,2", "and the device model")
t.assertEqual(Xcode.parseSupport("16.4 (20E247)").build, "20E247", "older names carry the build")
local support = Xcode.supportRows({
	{platform = "iOS", name = "17.5 (21F79)", path = "/s/17.5", bytes = 3e9},
	{platform = "iOS", name = "iPhone17,1 26.0 (23A341)", path = "/s/26.0", bytes = 4e9},
	{platform = "iOS", name = "9.3 (13E230)", path = "/s/9.3", bytes = 2e9},
	{platform = "watchOS", name = "11.5 (22T572)", path = "/s/w11.5", bytes = 1e9},
})
t.assertEqual(support[1].name, "iOS 26.0", "the newest version sorts first")
t.expect(support[1].keep and not support[2].keep, "only the newest version per platform is kept")
t.assertEqual(support[3].name, "iOS 9.3", "versions compare numerically, not as text")
t.expect(support[4].keep, "each platform keeps its own newest version")
local derived = Xcode.derivedRows({
	{name = "App-abcdefghijklmnop", path = "/d/App", bytes = 2e9, workspace = "/p/App/App.xcodeproj", exists = true},
	{name = "Old-qrstuvwxyzabcdef", path = "/d/Old", bytes = 1e9, workspace = "/p/Old/Old.xcworkspace", exists = false},
	{name = "Mystery-hijklmnopqrstuvw", path = "/d/Mystery", bytes = 5e9},
})
t.assertEqual(derived[1].name, "Old", "missing projects come first")
t.expect(derived[1].missing and derived[1].status == "Missing", "a missing workspace is flagged")
t.assertEqual(derived[3].status, "Present", "present projects are not flagged")
t.assertEqual(derived[2].name, "Mystery", "folders without info.plist fall back to their name")
t.assertEqual(derived[2].status, "Unknown", "an unknown workspace is never called missing")
local archives = Xcode.archiveRows({
	{name = "B.xcarchive", path = "/a/B", date = "2026-01-01", bytes = 1e9, plist = {Name = "Beta", CreationDate = "2026-01-01T00:00:00Z",
		ApplicationProperties = {CFBundleShortVersionString = "2.0", CFBundleVersion = "5"}}},
	{name = "A.xcarchive", path = "/a/A", date = "2024-05-02", bytes = 1e9},
})
t.assertEqual(archives[1].date, "2024-05-02", "archives are oldest first")
t.assertEqual(archives[2].subtitle, "Version 2.0 (5)", "archive versions come from Info.plist")
t.assertEqual(archives[1].name, "A", "archives without Info.plist keep their folder name")
t.assertEqual(Xcode.total(support, function(row) return not row.keep end), 5e9, "totals can be filtered")

-- Leftovers: only folders no installed app or macOS claims.
local apps = {{name = "Visual Studio Code.app", bundleId = "com.microsoft.VSCode"}, {name = "Slack.app", bundleId = "com.tinyspeck.slackmacgap"},
	{name = "Google Chrome.app", bundleId = "com.google.Chrome"}}
t.assertEqual(Leftovers.identifier("group.com.x.shared"), "com.x.shared", "group containers name their bundle")
t.assertEqual(Leftovers.identifier("ABCDE12345.com.x.shared"), "com.x.shared", "team-prefixed containers name their bundle")
t.assertEqual(Leftovers.identifier("com.x.app.savedState"), "com.x.app", "saved state names its bundle")
t.assertEqual(Leftovers.identifier("Code"), nil, "plain names are not identifiers")
local installed = Leftovers.index(apps)
local function tier(name, byName) return Leftovers.classify(name, byName, installed) end
t.assertEqual(tier("com.oldvendor.Photo"), "high", "an uninstalled app's container is high confidence")
t.assertEqual(tier("com.google.Earth"), "medium", "a vendor with other installed apps is medium confidence")
t.assertEqual(tier("OldTool", true), "low", "a plain name nobody claims is low confidence")
t.assertEqual(tier("OldTool"), nil, "plain names count only where apps use names, such as Application Support")
for _, case in ipairs({{"com.microsoft.VSCode"}, {"com.microsoft.VSCode.helper"}, {"com.apple.mail"}, {"Code", true},
	{"Google", true}, {"MobileSync", true}, {"SomeCache"}, {".hidden", true}}) do
	t.assertEqual(tier(case[1], case[2]), nil, "never a leftover: " .. case[1])
end
local helperInstalled = Leftovers.index({{bundleId = "com.x.editor.helper"}})
t.assertEqual(Leftovers.classify("com.x.editor", false, helperInstalled), nil, "an installed helper claims its host's folder")

-- Projects: git parsing and grouping.
local git = Projects.parseGit("## main...origin/main [ahead 2]\n M a.rs\n?? b.rs\n")
t.expect(git and git.branch == "main" and git.changes == 2 and git.ahead == 2 and not git.clean, "git status is parsed")
t.expect(Projects.parseGit("## main...origin/main\n").clean, "a tree without changes or unpushed commits is clean")
t.assertEqual(Projects.parseGit("fatal: not a git repository"), nil, "non-repositories have no git state")
t.assertEqual(Projects.gitText(git), "main · 2 uncommitted changes, 2 unpushed", "git state reads plainly")
local model = Model.new("/Users/test")
model.resources:add("developer", {id = "p1-node", name = "Node modules · app", subtitle = "x", path = "/Users/test/Developer/app/node_modules",
	project = "/Users/test/Developer/app", artifact = "Node modules", policy = "Review", action = "finder"})
model.resources:add("developer", {id = "p1-next", name = "Next.js build output · app", subtitle = "x", path = "/Users/test/Developer/app/.next",
	project = "/Users/test/Developer/app", artifact = "Next.js build output", policy = "Review", action = "finder"})
model.resources:add("developer", {id = "p2-target", name = "Rust build output · tool", subtitle = "x", path = "/Users/test/Code/tool/target",
	project = "/Users/test/Code/tool", artifact = "Rust build output", policy = "Review", action = "finder"})
model.measurements["p1-node"] = {bytes = 3e9, status = "complete"}
model.measurements["p1-next"] = {bytes = 1e9, status = "complete"}
model.measurements["p2-target"] = {bytes = 2e9, status = "complete"}
local now = os.time({year = 2026, month = 9, day = 27, hour = 12})
local info = {["/Users/test/Developer/app"] = {modified = now - 200 * 86400, git = Projects.parseGit("## main\n"), loaded = true},
	["/Users/test/Code/tool"] = {modified = now - 3 * 86400, loaded = true}}
local groups = Projects.groups(model, info, now)
t.assertEqual(#groups, 2, "artifacts group by project")
t.assertEqual(groups[1].bytes, 4e9, "a project totals its artifacts")
t.assertEqual(groups[1].artifactText, "Node modules, Next.js build output", "a project lists its artifact kinds")
t.assertEqual(groups[1].ageText, "200 days ago", "age comes from the project folder")
t.assertEqual(groups[2].gitText, "Not in git", "projects outside git say so")
t.assertEqual(#Projects.groups(model, info, now, Projects.filters[2]), 1, "the stale filter keeps untouched projects")
t.assertEqual(#Projects.groups(model, info, now, Projects.filters[3]), 1, "the clean filter keeps clean git trees")
t.assertEqual(Projects.groups(model, {}, now)[1].gitText, "Checking…", "git state shows progress until read")

-- Basket: refuses system and standard folders, never double counts.
local home = "/Users/test"
for _, path in ipairs({"/", "/System", "/System/Library/Caches", "/Applications", "/Library", "/Users", home, home .. "/Documents",
	home .. "/Library", home .. "/Library/Caches", "/Volumes/Backup", "/System/Volumes/Data", "relative/path", home .. "/a/../b"}) do
	t.expect(not Basket.validate(path, home), "refused: " .. path)
end
for _, path in ipairs({home .. "/Downloads/installer.dmg", home .. "/Library/Caches/com.x", "/Applications/Old.app"}) do
	t.expect(Basket.validate(path, home), "allowed: " .. path)
end
local basket = Basket.new(home)
t.expect(basket:add({path = home .. "/Library/Developer/Xcode/DerivedData/App", bytes = 2e9}), "a folder can be marked")
t.expect(not basket:add({path = home .. "/Library/Developer/Xcode/DerivedData/App/Build", bytes = 1e9}), "a child of a marked folder is refused")
t.expect(basket:add({path = home .. "/Library/Developer/Xcode/DerivedData", bytes = 5e9}), "a parent replaces its marked children")
t.assertEqual(basket:count(), 1, "the parent absorbed its child")
t.assertEqual(basket:summary(), "1 item · 5.0 GB", "the basket totals marked bytes")
t.expect(basket:remove(home .. "/Library/Developer/Xcode/DerivedData") and basket:count() == 0, "items can be unmarked")

-- Operation log lines round-trip and never span lines.
local line = OperationLog.format({action = "Move to Trash", ok = true, bytes = 2e9, target = "/x/a\tb\nc"}, 0)
t.expect(not line:find("\n", 1, true), "one action is one line")
local entry = OperationLog.parse(line)
t.expect(entry.ok and entry.bytes == 2e9 and entry.target == "/x/a b c", "log lines parse back")
local rows = OperationLog.rows({line, OperationLog.format({action = "Empty Trash", ok = false, detail = "denied"}, 60)})
t.assertEqual(rows[1].name, "Empty Trash", "history is newest first")
t.assertEqual(rows[1].result, "Failed: denied", "failures keep their reason")

-- History: opt-in totals and changes.
local a = {time = now - 10 * 86400, totals = {developer = 10e9, documents = 5e9, trash = 1e9}}
local b = {time = now, totals = {developer = 14e9, documents = 4e9}}
local decoded = History.decode(History.encode({a, b}))
t.assertEqual(decoded[2].totals.developer, 14e9, "history round-trips")
local changes = History.changes(model, decoded, 30, 4, now)
t.assertEqual(changes.rows[1].id, "developer", "the largest change comes first")
t.assertEqual(changes.rows[1].text, "+4.0 GB", "growth is signed")
t.assertEqual(changes.rows[2].text, "−1.0 GB", "shrinkage is signed")
t.assertEqual(#changes.rows, 2, "categories missing at either end are skipped")
t.assertEqual(History.changes(model, {a}, 30), nil, "one scan has no changes")
local long = {}
for index = 1, History.keep + 5 do History.append(long, {time = index, totals = {}}) end
t.assertEqual(#long, History.keep, "history keeps a bounded number of scans")

-- Map tree: focus, rings and roll-ups.
local map = Model.new("/Users/test")
map.measurements.derived = {bytes = 40e9, status = "complete"}
map.measurements.simulators = {bytes = 20e9, status = "complete"}
map.measurements.downloads = {bytes = 30e9, status = "complete"}
map.measurements.npm = {bytes = 1e6, status = "complete"}
local nodes, total = MapTree.nodes(map, "")
t.assertEqual(total, 90e9 + 1e6, "the map totals the focus")
local byId = {}
for _, node in ipairs(nodes) do byId[node.id] = node end
t.assertEqual(byId.developer.ring, 1, "categories form the first ring")
t.assertEqual(byId.xcode.parent, "developer", "groups sit inside their category")
t.assertEqual(byId.derived.color, byId.developer.color, "descendants share their category color")
t.expect(byId.derived.hatched, "rebuildable resources are hatched")
t.assertEqual(byId.npm, nil, "slivers fold into their parent's roll-up")
local focused = MapTree.nodes(map, "xcode")
t.assertEqual(focused[1].parent, nil, "a focus starts a new first ring")
t.assertEqual(MapTree.path(map, "xcode")[3].name, "Xcode", "the breadcrumb leads from All Storage to the focus")
t.assertEqual(MapTree.worthALook(map, "developer")[1].id, "derived", "worth a look lists rebuildable resources under the focus")
t.expect(MapTree.describe(map, "xcode", total):find("Developer › Xcode", 1, true) == 1, "hover text names the path")

-- Overview: hidden space and available capacity.
local disk = {totalKb = 1000e9 / 1024, freeKb = 100e9 / 1024}
local hidden = Overview.hidden(disk, {important = 130e9}, 3, 2)
t.assertEqual(hidden[1].value, "30.0 GB", "purgeable space is important minus free")
t.assertEqual(hidden[2].value, "3", "snapshots are counted")
t.assertEqual(#Overview.hidden(disk, {important = 90e9}, 0, 0), 0, "nothing hidden shows nothing")
t.assertEqual(Overview.summary(map, disk, {important = 130e9}).subtitle, "100.0 GB free · 130.0 GB available of 1.00 TB",
	"available includes purgeable space")

-- Updates: installers found on disk join installer apps.
local found = Updates.installers(map, {{path = "/Users/test/Downloads/Tool.dmg", bytes = 2e8}, {path = "/Users/test/Desktop/x.PKG", bytes = 9e8}})
t.assertEqual(found[1].kind, "Installer package in Desktop", "installers say what and where they are")
t.assertEqual(found[2].name, "Tool.dmg", "installers are largest first")

-- Logical sizes and iCloud-only files travel from the scan to the inspector.
local Inventory = require("apps.diskmap.models.Inventory")
local Inspector = require("apps.diskmap.models.Inspector")
local cloudModel = Model.new("/Users/test")
local _, cloudIds = Inventory.plan(cloudModel)
Inventory.begin(cloudModel, cloudIds)
local trees, states = {}, {}
for index in ipairs(cloudIds) do trees[index] = {kb = 1024}; states[index] = "measured" end
trees[1] = {kb = 1024, logicalKb = 1024 * 1024, cloudKb = 2048, cloudFiles = 3}
Inventory.progress(cloudModel, cloudIds, {completed = #cloudIds, total = #cloudIds, trees = trees, rootStates = states})
local measured = cloudModel.measurements[cloudIds[1]]
t.expect(measured.logicalBytes == 1024 * 1024 * 1024 and measured.cloudFiles == 3 and measured.cloudBytes == 2048 * 1024,
	"measurements keep logical size and iCloud-only files")
local cloudBytes, cloudFiles = Inventory.cloud(cloudModel)
t.expect(cloudFiles == 3 and cloudBytes == 2048 * 1024, "iCloud-only files are totalled across resources")
local location = Inspector.details(cloudModel, cloudIds[1]).location
t.expect(location:find("logical size", 1, true) and location:find("3 files in iCloud only", 1, true), "the inspector explains both")
local hiddenCloud = Overview.hidden(disk, nil, 0, 0, cloudBytes, cloudFiles)
t.assertEqual(hiddenCloud[1].id, "icloud", "the overview lists iCloud-only files")

os.exit(t.summary() and 0 or 1)
