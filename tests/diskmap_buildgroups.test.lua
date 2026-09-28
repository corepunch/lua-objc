_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Scan = require("apps.diskmap.controllers.ScanController")
local Categories = require("apps.diskmap.models.Categories")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Projects = require("apps.diskmap.models.Projects")
local Developer = require("apps.diskmap.models.Developer")

-- Build folders found in projects add up per ecosystem: "Node modules:
-- 1.2 GB in 3 projects", drillable to each project's folder.
local home = "/Users/test"
local function entry(id, project, artifact, dirName, policy)
	return {id = id, name = artifact .. " · " .. project, path = home .. "/Documents/" .. project .. "/" .. dirName,
		project = home .. "/Documents/" .. project, projectName = project, artifact = artifact,
		policy = policy or "Review", action = policy == "Rebuildable" and "trash" or "finder", reviewThreshold = 500e6}
end

-- Nothing found: no ecosystem group.
local empty = Model.new(home)
t.expect(Scan.register(empty, {}), "an empty discovery registers nothing")
t.expect(empty.resources:find("build-node-modules") == nil, "no group exists without build folders")
t.assertEqual(#Cleanup.buildGroups(empty), 0, "no ecosystem totals without build folders")

local model = Model.new(home)
local entries = {
	entry("nm-site", "site", "Node modules", "node_modules", "Rebuildable"),
	entry("nm-blog", "blog", "Node modules", "node_modules", "Rebuildable"),
	entry("nm-shop", "shop", "Node modules", "node_modules", "Rebuildable"),
	entry("rust-shop", "shop", "Rust build output", "target"),
	entry("nm-site-again", "site", "Node modules", "node_modules", "Rebuildable"),
}
entries[5].id = "nm-site-duplicate"
t.expect(Scan.register(model, entries), "discovered folders register")
local group = model.resources:find("build-node-modules")
t.expect(group ~= nil and not group:isLeaf() and group:getParent().id == "developer", "Node modules is one group under Developer")
t.assertEqual(#group:getChildren(), 3, "the same folder reached from two roots is counted once")
t.expect(model.resources:find("build-rust-build-output") ~= nil, "each ecosystem has its own group")
t.expect(group.subtitle:find("Downloaded code libraries", 1, true) ~= nil, "the group explains itself in plain words")
t.expect(Scan.register(model, {entry("nm-new", "new", "Node modules", "node_modules")}), "later folders join the existing group")
t.assertEqual(#group:getChildren(), 4, "a later scan adds to the group")

-- Each folder is small; together they cross the review threshold.
local sizes = {["nm-site"] = 200e6, ["nm-blog"] = 180e6, ["nm-shop"] = 150e6, ["nm-new"] = 90e6, ["rust-shop"] = 300e6}
for id, bytes in pairs(sizes) do model.measurements[id] = {status = "complete", bytes = bytes} end
local row = Categories.row(model, "build-node-modules")
t.assertEqual(row.bytes, 620e6, "the group totals its folders")
local suggestions = {}
for _, value in ipairs(Cleanup.suggestions(model)) do suggestions[value.id] = value end
local nm = suggestions["build-node-modules"]
t.expect(nm ~= nil, "folders under the per-folder threshold still surface as their ecosystem")
t.expect(suggestions["nm-site"] == nil, "folders are not suggested one by one")
t.assertEqual(nm.bytes, 620e6, "the suggestion totals every project")
t.assertEqual(nm.projects, 4, "the suggestion counts projects")
t.expect(nm.subtitle:find("In 4 projects", 1, true) ~= nil, "the row says how many projects")
t.assertEqual(nm.impact, "Needs review", "one unproven folder keeps the group in review")
t.expect(suggestions["build-rust-build-output"] == nil, "an ecosystem under the threshold is not suggested")

-- Every folder proven: the group is rebuildable. Keep removes a folder.
model.resources:find("nm-new").policy = "Rebuildable"
t.assertEqual(Cleanup.suggestions(model)[1].impact, "Safe/rebuildable", "a fully proven group is rebuildable")
model.kept["nm-site"] = true
local kept
for _, value in ipairs(Cleanup.suggestions(model)) do if value.id == "build-node-modules" then kept = value end end
t.expect(kept == nil, "keeping a folder takes it out of the total, below the threshold")
model.kept["nm-site"] = nil
local checked = Recommendations.checked(model, {}, "")
for _, value in ipairs(checked) do t.expect(value.id ~= "nm-blog", "build folders are checked as their group, not alone") end

-- One project with several artifacts stays one project on the Projects page.
local projects = {}
for _, value in ipairs(Projects.groups(model, {}, os.time())) do projects[value.name] = value end
t.expect(projects.shop and #projects.shop.artifacts == 2, "a project lists each of its build folders")
t.assertEqual(projects.shop.bytes, 450e6, "a project totals its own folders")

-- The Developer page shows one row per ecosystem.
local rows = {}
for _, section in ipairs(Developer.presentation(model, "").sections) do
	for _, value in ipairs(section.rows) do rows[value.id] = value end
end
t.expect(rows["build-node-modules"] and rows["build-node-modules"].group, "the Developer page rolls folders into their ecosystem")
t.expect(rows["nm-site"] == nil, "folders are listed inside their ecosystem, not beside it")

os.exit(t.summary() and 0 or 1)
