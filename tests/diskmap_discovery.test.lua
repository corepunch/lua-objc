_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Scan = require("apps.diskmap.controllers.ScanController")
local Catalog = require("apps.diskmap.Catalog")
local Inventory = require("apps.diskmap.models.Inventory")

local rules = Catalog.discoveryRules("/Users/test")
t.assertEqual(rules[1].rules[1].dirName, "node_modules", "project dependency convention is cataloged")
t.assertEqual(rules[1].rules[1].markerFile, "package.json", "generated folders require project evidence")
t.assertEqual(rules[2].root, "/Applications", "installer discovery is limited to Applications")

local model = Model.new("/Users/test")
local measuredPaths
local scanner = Scan.new(model, {
	discoverEntries = function(_, done)
		done({
			{id = "discovered-node-modules", parentId = "developer", name = "Node modules · demo", subtitle = "Project dependencies", path = "/Users/test/Developer/demo/node_modules", action = "finder", policy = "Review"},
			{id = "discovered-installer", parentId = "applications", name = "Install macOS Tahoe.app", subtitle = "Full installer", path = "/Applications/Install macOS Tahoe.app", action = "finder", policy = "Review", reviewThreshold = 5e9},
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
t.assertEqual(model.resources:find("discovered-installer"):getParent().id, "applications", "installer belongs to Applications")
local paths = {}; for _, path in ipairs(measuredPaths) do paths[path] = true end
t.expect(paths["/Users/test/Developer/demo/node_modules"], "generated folders receive independent measurements")
t.expect(paths["/Applications/Install macOS Tahoe.app"], "installer apps receive independent measurements")
local _, _, exclusions = Inventory.plan(model)
local excluded = {}; for _, path in ipairs(exclusions) do excluded[path] = true end
t.expect(excluded["/Users/test/Developer/demo/node_modules"], "generated folders are removed from the Developer residual scan")
t.expect(excluded["/Applications/Install macOS Tahoe.app"], "installers are removed from the Applications residual scan")
scanner:dispose()
os.exit(t.summary() and 0 or 1)
