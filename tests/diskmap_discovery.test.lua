_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Scan = require("apps.diskmap.controllers.ScanController")
local Catalog = require("apps.diskmap.Catalog")
local Inventory = require("apps.diskmap.models.Inventory")
local System = require("apps.diskmap.services.System")

local rules = Catalog.discoveryRules("/Users/test")
t.assertEqual(rules[1].rules[1].dirName, "node_modules", "project dependency convention is cataloged")
t.assertEqual(rules[1].rules[1].markerFile, "package.json", "generated folders require project evidence")
t.assertEqual(rules[2].root, "/Applications", "shared application discovery uses Applications")
t.expect(rules[2].applications, "shared app bundles are individually discovered")
t.assertEqual(rules[3].root, "/Users/test/Applications", "personal application discovery uses the user's Applications folder")
local originalCommand, finds = System.command, {}
System.command = function(argv, done)
	table.insert(finds, argv)
	local output = argv[2] == "/Applications" and "/Applications/Editor.app\n/Applications/Install macOS Tahoe.app\n" or
		argv[2] == "/Users/test/Applications" and "/Users/test/Applications/Personal Editor.app\n" or ""
	done(true, output)
end
local discovered
System.discoverEntries("/Users/test", function(entries) discovered = entries end)
System.command = originalCommand
t.assertEqual(#finds, 3, "discovery checks project outputs and both Applications folders")
t.assertEqual(finds[2][7], "-name", "application search names app bundles directly under the folder")
t.assertEqual(finds[2][#finds[2]], "-print", "application search returns paths only")
local appEntries = {}; for _, entry in ipairs(discovered) do appEntries[entry.path] = entry end
t.expect(appEntries["/Applications/Editor.app"] and appEntries["/Users/test/Applications/Personal Editor.app"], "individual shared and personal apps are recognized")
t.assertEqual(appEntries["/Applications/Editor.app"].parentId, "apps-system", "shared app paths belong to shared Applications")
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
			{id = "discovered-editor", parentId = "apps-system", name = "Visual Studio Code.app", subtitle = "Installed application", path = "/Applications/Visual Studio Code.app", action = "finder", policy = "Review", reviewThreshold = 1e9},
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
