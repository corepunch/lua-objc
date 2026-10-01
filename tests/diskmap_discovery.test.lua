_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Scan = require("apps.diskmap.controllers.ScanController")
local Catalog = require("apps.diskmap.Catalog")
local Categories = require("apps.diskmap.models.Categories")
local Inventory = require("apps.diskmap.models.Inventory")
local System = require("apps.diskmap.services.System")

local rules = Catalog.discoveryRules("/Users/test")
t.assertEqual(rules[1].rules[1].dirName, "node_modules", "project dependency convention is cataloged")
t.assertEqual(rules[1].rules[1].markers[1], "package.json", "generated folders require project evidence")
t.assertEqual(rules[2].root, "/Applications", "shared application discovery uses Applications")
t.expect(rules[2].applications, "shared app bundles are individually discovered")
t.assertEqual(rules[3].root, "/Users/test/Applications", "personal application discovery uses the user's Applications folder")

-- Where projects are searched: common project folders once each, and the
-- folders macOS protects only with Full Disk Access, so no prompt appears.
local function has(list, value) for _, item in ipairs(list) do if item == value then return true end end return false end
local roots = rules[1].roots
t.expect(has(roots, "/Users/test/Developer") and has(roots, "/Users/test/GitHub") and has(roots, "/Users/test/Sites"), "common project folders are searched")
t.expect(has(roots, "/Users/test/code") and not has(roots, "/Users/test/Code"), "folders that differ only in case are searched once")
t.expect(not has(roots, "/Users/test/Documents") and not has(roots, "/Users/test/Desktop"), "protected folders need Full Disk Access")
local granted = Catalog.discoveryRules("/Users/test", {"/Volumes/Work/src", "/Users/test/developer"}, true)[1].roots
t.expect(has(granted, "/Users/test/Documents") and has(granted, "/Users/test/Desktop")
	and has(granted, "/Users/test/Library/Mobile Documents/com~apple~CloudDocs"), "with access, Documents, Desktop and iCloud Drive are searched")
t.expect(has(granted, "/Volumes/Work/src") and not has(granted, "/Users/test/developer"), "added folders join the list without duplicates")

-- The search prunes version control, the Trash and packages, caps its depth
-- and names each shared folder ("target", "build") once.
local argv = Catalog.findArguments({"/a", "/b"}, Catalog.buildRules())
t.assertEqual(argv[2] .. " " .. argv[3], "/a /b", "several roots are searched in one pass")
t.assertEqual(argv[4] .. " " .. argv[5], "-maxdepth " .. Catalog.discoveryDepth, "the depth is capped")
local joined = table.concat(argv, " ")
t.expect(joined:find("-name .git", 1, true) and joined:find("-name *.app", 1, true) and joined:find("-name .Trash", 1, true), "git, apps and the Trash are skipped")
local targets = 0
for _, value in ipairs(argv) do if value == "target" then targets = targets + 1 end end
t.assertEqual(targets, 1, "a folder name shared by two ecosystems is searched once")
t.assertEqual(argv[#argv], "-print", "matched folders are printed, never descended")
local ruleNames = {}
for _, rule in ipairs(Catalog.buildRules()) do ruleNames[rule.dirName .. ":" .. rule.markers[1]] = rule end
t.expect(ruleNames["Pods:Podfile"] and ruleNames["venv:pyproject.toml"] and ruleNames[".venv:pyproject.toml"], "Pods and both virtual environment names are recognized")
t.expect(has(ruleNames["venv:pyproject.toml"].markers, "requirements.txt") and has(ruleNames[".venv:pyproject.toml"].markers, "uv.lock"), "virtual environments beside any Python project file count")
t.expect(has(ruleNames[".next:next.config.js"].markers, "package.json"), "a Next.js build needs no next.config")

-- Project names come from the repository; a second proof inside the folder
-- makes a dependency folder Rebuildable.
local Projects = require("apps.diskmap.models.Projects")
t.assertEqual(Projects.displayName("/p/my-app/apps/mobile/ios", "/p/my-app"), "my-app/apps/mobile/ios", "a monorepo folder is named from its repository")
t.assertEqual(Projects.displayName("/p/site", "/p/site"), "site", "a repository's own folder keeps its name")
t.assertEqual(Projects.displayName("/p/site", nil), "site", "a folder outside git keeps its name")
t.assertEqual(Projects.lastWorked("stat: x: No such file\n1700000000\n1700000500\n1600000000\n"), 1700000500, "the newest file time wins; messages are ignored")
t.assertEqual(Projects.lastWorked("1\n2\n3\n", 2), 2, "only the budget's worth of files count")
t.assertEqual(Projects.lastWorked(""), nil, "no files means no date")

local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/diskmap-discovery.XXXXXXXX"))
local tmp = pipe:read("*l"); pipe:close()
local function touch(path) os.execute("/bin/mkdir -p '" .. path:match("^(.*)/[^/]+$") .. "'"); local f = assert(io.open(path, "w")); f:write("x"); f:close() end
touch(tmp .. "/site/package.json"); touch(tmp .. "/site/node_modules/.package-lock.json")
touch(tmp .. "/old/package.json"); os.execute("/bin/mkdir -p " .. tmp .. "/old/node_modules")
touch(tmp .. "/mono/.git/HEAD"); touch(tmp .. "/mono/apps/ios/Podfile"); touch(tmp .. "/mono/apps/ios/Pods/Manifest.lock")
touch(tmp .. "/py/requirements.txt"); touch(tmp .. "/py/venv/pyvenv.cfg")
os.execute("/bin/mkdir -p " .. tmp .. "/stray/node_modules")
-- CMake: marker beside, CMakeCache.txt inside as the proof; a bare "build" is nothing.
touch(tmp .. "/cmakeapp/CMakeLists.txt"); touch(tmp .. "/cmakeapp/build/CMakeCache.txt")
touch(tmp .. "/unconfigured/CMakeLists.txt"); os.execute("/bin/mkdir -p " .. tmp .. "/unconfigured/build")
os.execute("/bin/mkdir -p " .. tmp .. "/plainbuild/build")
-- A project-local DerivedData folder needs an Xcode project beside it.
os.execute("/bin/mkdir -p " .. tmp .. "/iosapp/App.xcodeproj"); touch(tmp .. "/iosapp/DerivedData/Build/Products/x")
touch(tmp .. "/noproject/DerivedData/Build/Products/x")
local originalCommand, originalAccess, finds = System.command, System.hasFullDiskAccess, {}
System.hasFullDiskAccess = function() return false end
System.command = function(argv, done)
	table.insert(finds, argv)
	if argv[2] == tmp then
		done(false, table.concat({tmp .. "/site/node_modules", tmp .. "/old/node_modules", tmp .. "/mono/apps/ios/Pods",
			tmp .. "/py/venv", tmp .. "/stray/node_modules", tmp .. "/cmakeapp/build", tmp .. "/unconfigured/build",
			tmp .. "/plainbuild/build", tmp .. "/iosapp/DerivedData", tmp .. "/noproject/DerivedData", "find: " .. tmp .. "/locked: Permission denied"}, "\n"))
		return
	end
	local output = argv[2] == "/Applications" and "/Applications/Editor.app\n/Applications/Install macOS Tahoe.app\n" or
		argv[2] == "/Users/test/Applications" and "/Users/test/Applications/Personal Editor.app\n" or ""
	done(true, output)
end
local discovered
System.discoverEntries("/Users/test", function(entries) discovered = entries end, {tmp})
System.command, System.hasFullDiskAccess = originalCommand, originalAccess
t.assertEqual(#finds, 3, "discovery searches existing project folders in one pass, then both Applications folders")
t.assertEqual(finds[2][7], "-name", "application search names app bundles directly under the folder")
t.assertEqual(finds[2][#finds[2]], "-print", "application search returns paths only")
local byPath = {}; for _, entry in ipairs(discovered) do byPath[entry.path] = entry end
local site, old, pods, venv = byPath[tmp .. "/site/node_modules"], byPath[tmp .. "/old/node_modules"], byPath[tmp .. "/mono/apps/ios/Pods"], byPath[tmp .. "/py/venv"]
t.expect(site and site.policy == "Rebuildable" and site.action == "trash" and site.proof == "marker and contents", "node_modules with npm's own lock inside is Rebuildable")
t.expect(old and old.policy == "Review" and old.action == "finder", "a folder proven only by its project file stays Review")
t.expect(pods and pods.artifact == "CocoaPods dependencies" and pods.projectName == "mono/apps/ios", "Pods are found and named from their repository")
t.expect(venv and venv.artifact == "Python virtual environments" and venv.policy == "Review", "a venv beside requirements.txt is found and stays Review")
t.expect(byPath[tmp .. "/stray/node_modules"] == nil, "a folder without its project file is never claimed")
local cmake, unconfigured, derivedLocal = byPath[tmp .. "/cmakeapp/build"], byPath[tmp .. "/unconfigured/build"], byPath[tmp .. "/iosapp/DerivedData"]
t.expect(cmake and cmake.artifact == "CMake build output" and cmake.policy == "Rebuildable" and cmake.marker == tmp .. "/cmakeapp/CMakeLists.txt",
	"a build folder with CMakeCache.txt beside CMakeLists.txt is Rebuildable CMake output")
t.expect(unconfigured and unconfigured.policy == "Review", "a build folder never configured is found by its marker but stays Review")
t.assertEqual(byPath[tmp .. "/plainbuild/build"], nil, "a folder named build without a project marker is never claimed")
t.expect(derivedLocal and derivedLocal.artifact == "Xcode project build data" and derivedLocal.policy == "Rebuildable"
	and derivedLocal.marker == tmp .. "/iosapp/App.xcodeproj", "project-local DerivedData beside an Xcode project is recognised")
t.assertEqual(byPath[tmp .. "/noproject/DerivedData"], nil, "DerivedData without an Xcode project is not claimed")
t.assertEqual(cmake.project, tmp .. "/cmakeapp", "an artifact belongs to the project that owns it")
t.assertEqual(site.marker, tmp .. "/site/package.json", "each folder remembers the file that proved it")
os.execute("/bin/rm -rf " .. tmp)
local appEntries = {}; for _, entry in ipairs(discovered) do appEntries[entry.path] = entry end
t.expect(appEntries["/Applications/Editor.app"] and appEntries["/Users/test/Applications/Personal Editor.app"], "individual shared and personal apps are recognized")
t.assertEqual(appEntries["/Applications/Editor.app"].parentId, "apps-system", "shared app paths belong to shared Applications")
t.assertEqual(appEntries["/Applications/Editor.app"].fileIcon, "/Applications/Editor.app", "discovered apps use their bundle paths for native artwork")
t.assertEqual(appEntries["/Users/test/Applications/Personal Editor.app"].parentId, "apps-user", "personal app paths belong to personal Applications")
t.assertEqual(appEntries["/Applications/Editor.app"].reviewThreshold, 1e9, "regular app review uses its threshold")
t.assertEqual(appEntries["/Applications/Install macOS Tahoe.app"].reviewThreshold, 5e9, "installer receives installer-specific review threshold")

local model = Model.new("/Users/test")
local measuredPaths
local scanner = Scan.new(model, {
	discoverEntries = function(_, done)
		done({
			{id = "discovered-node-modules", parentId = "developer", name = "Node modules · demo", subtitle = "Project dependencies", path = "/Users/test/Developer/demo/node_modules", action = "finder", policy = "Review"},
			{id = "discovered-installer", parentId = "apps-system", name = "Install macOS Tahoe.app", subtitle = "Full installer", path = "/Applications/Install macOS Tahoe.app", action = "finder", policy = "Review", reviewThreshold = 5e9},
			{id = "discovered-editor", parentId = "apps-system", name = "Visual Studio Code.app", subtitle = "Installed application", path = "/Applications/Visual Studio Code.app", fileIcon = "/Applications/Visual Studio Code.app", action = "finder", policy = "Review", reviewThreshold = 1e9},
			{id = "discovered-personal-app", parentId = "apps-user", name = "Editor.app", subtitle = "Installed application", path = "/Users/test/Applications/Editor.app", action = "finder", policy = "Review", reviewThreshold = 1e9},
		})
	end,
	start = function(paths) measuredPaths = paths; return {} end,
	await = function(_, completion)
		local result = {trees = {}, rootStates = {}}
		for index = 1, #measuredPaths do result.rootStates[index] = "missing" end
		completion(result)
	end,
	cancel = function() end,
	diskSpace = function() return {totalKb = 0, freeKb = 0} end,
}, "/Users/test")
scanner:start()
t.assertEqual(model.resources:find("discovered-node-modules"):getParent().id, "developer", "generated folder belongs to Developer")
t.assertEqual(model.resources:find("discovered-installer"):getParent().id, "apps-system", "installer belongs to shared Applications")
t.assertEqual(model.resources:find("discovered-editor"):getParent().id, "apps-system", "regular apps belong to shared Applications")
t.assertEqual(model.resources:find("discovered-personal-app"):getParent().id, "apps-user", "personal apps belong to the personal Applications category")
t.assertEqual(model.resources:find("discovered-editor").reviewThreshold, 1e9, "large installed apps become review suggestions without cleanup eligibility")
t.assertEqual(model.resources:find("discovered-editor").action, "finder", "installed apps remain review-only")
local categoryApp
for _, row in ipairs(Categories.rows(model, "apps-system")) do if row.id == "discovered-editor" then categoryApp = row end end
t.assertEqual(categoryApp.fileIcon, "/Applications/Visual Studio Code.app", "application rows retain their native icon path")
local managedApp
for _, row in ipairs(Categories.managementRows(model, "applications")) do if row.id == "discovered-editor" then managedApp = row end end
t.assertEqual(managedApp.fileIcon, "/Applications/Visual Studio Code.app", "management rows retain their native icon path")
local paths = {}; for _, path in ipairs(measuredPaths) do paths[path] = true end
t.expect(paths["/Users/test/Developer/demo/node_modules"], "generated folders receive independent measurements")
t.expect(paths["/Applications/Install macOS Tahoe.app"], "installer apps receive independent measurements")
t.expect(paths["/Applications/Visual Studio Code.app"], "installed app bundles receive independent measurements")
t.expect(paths["/Users/test/Applications/Editor.app"], "personal app bundles receive independent measurements")
local _, _, exclusions = Inventory.plan(model)
local excluded = {}; for _, path in ipairs(exclusions) do excluded[path] = true end
t.expect(excluded["/Users/test/Developer/demo/node_modules"], "generated folders are removed from the Developer residual scan")
t.expect(excluded["/Applications/Install macOS Tahoe.app"], "installers are removed from the Applications residual scan")
t.expect(excluded["/Applications/Visual Studio Code.app"], "apps are removed from the shared Applications residual scan")
t.expect(excluded["/Users/test/Applications/Editor.app"], "apps are removed from the personal Applications residual scan")
scanner:dispose()
os.exit(t.summary() and 0 or 1)
