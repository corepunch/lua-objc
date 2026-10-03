_G.__headless = true
local t = require("TestKit")
local Model = require("data.model")
local Harness = require("tests.support.diskmap")
local Contract = require("apps.diskmap.services.Contract")
local Mock = require("apps.diskmap.services.Mock")
local Keeps = require("apps.diskmap.models.Keeps")
local Inventories = require("apps.diskmap.models.Inventories")
local Suggestions = require("apps.diskmap.models.Suggestions")

t.expect(Contract.check(require("apps.diskmap.services.System")), "System implements the complete contract")
t.expect(Contract.check(Mock.new()), "Mock implements the complete contract")
t.expect(Contract.check(Mock.new({showcase = true})), "showcase implements the complete contract")
t.expect(not pcall(Contract.check, {home = "/Users/test"}), "incomplete providers fail at construction")

local modelKeys = {}
for _, name in ipairs({"Projects", "Inventories", "Keeps", "Session", "Applications", "Scans", "Locations", "Suggestions"}) do
	local module = require("apps.diskmap.models." .. name)
	local keys = {}; for key in pairs(module) do keys[key] = true end
	modelKeys[name] = keys
end
local totals = {}
for _, deferred in ipairs({false, true}) do
	local host = Harness.env({deferred = deferred})
	Model.bind(host.env.model)
	table.insert(totals, Suggestions:presentation("", host.env:sources()).eligibleBytes)
	for id in pairs(host.env.manifest.pages) do
		local page = Harness.mount(id, host)
		host.service.settle()
		page:update(host.env:state()); page:marksChanged()
		t.expect(page.refs ~= nil, id .. " renders with " .. (deferred and "deferred" or "immediate") .. " completions")
		t.assertEqual(host.env:page(id), page.request, id .. " is memoized")
		page:dispose()
	end
	t.expect(host.env.session.fullDiskAccess == nil, "unknown access stays unknown")
	host.env:dispose(); host.service.settle()
end
t.assertEqual(totals[1], totals[2], "cleanup amounts do not depend on callback timing")

local first, second = Harness.env({deferred = true}), Harness.env({deferred = true})
Model.bind(first.env.model); Keeps:toggle("derived")
first.env.scan.status = "first"
Model.bind(second.env.model)
t.expect(not Keeps:contains("derived") and second.env.scan.status ~= "first", "environments share neither Keep nor status")
t.expect(first.env:page("map") ~= second.env:page("map"), "each environment owns its requests")

-- Refresh while an old read is pending; only the new token publishes.
Model.bind(first.env.model)
first.env.inventories:load("applications", true)
first.env.inventories:load("applications", true)
local stock = Inventories:state("applications")
first.service.step(); first.service.step()
t.assertEqual(stock.pending, 2, "obsolete replies cannot finish a replacement read")
first.service.settle()
t.expect(stock.loaded and not stock.busy, "the replacement read completes")
first.env.inventories:load("worktrees", true)
local worktrees = Inventories:state("worktrees")
first.env:dispose(); first.service.settle()
t.expect(worktrees.busy, "disposal rejects late inventory results")

local page = Harness.mount("kinds", second)
page.request:showFiles("installers")
local sent = second.events[#second.events]
t.assertEqual(sent.name, "show", "Kinds uses the router")
t.assertEqual(sent.args[1], "files", "Kinds routes to Files")
t.assertEqual(sent.args[2].kind, "installers", "Kinds passes a named kind")
Harness.mount("overview", second).request:showMap("developer")
sent = second.events[#second.events]
t.assertEqual(sent.args[1], "map", "Overview routes to Map")
t.assertEqual(sent.args[2].focus, "developer", "Overview passes a named focus")
second.env:dispose()

-- A pending filesystem read must neither prevent a new scan's read nor
-- publish into it. The provider binds each callback to this environment.
local folders = Harness.env()
local pending = {}
folders.service.measure = function(paths, done) table.insert(pending, {paths = paths, done = done}) end
Model.bind(folders.env.model)
local filesystem = folders.env:page("filesystem")
filesystem:rendered()
t.assertEqual(#pending, 1, "first filesystem read starts")
folders.env.model.scan = {running = false}
filesystem:rendered()
t.assertEqual(#pending, 2, "a new scan starts its own filesystem read")
pending[1].done({900})
t.expect(folders.env.model.folderSizes == nil, "old filesystem read cannot publish")
pending[2].done({42})
t.assertEqual(folders.env.model.folderSizes[pending[2].paths[1]].bytes, 42, "new filesystem read publishes")
folders.env:dispose()

local marked = Harness.env()
local mapPage = Harness.mount("map", marked)
local item = mapPage.request.worth[1]
mapPage.actions.worth_1()
t.expect(marked.env.basket:isMarked(item.path), "Map's visible Mark action stages through the basket")
mapPage.actions.worth_1()
t.expect(not marked.env.basket:isMarked(item.path), "Map's visible Mark action toggles the same item")
local copy = marked.env.model.home .. "/Downloads/copy.iso"
marked.env.basket:toggle({path = copy, name = "copy.iso", bytes = 7000000, source = "Duplicates"})
local duplicate = marked.env:page("duplicates")
local menu = duplicate:rowMenu(nil, nil, {group = {files = {
	{path = marked.env.model.home .. "/Documents/original.iso", privateBytes = 7000000},
	{path = copy, privateBytes = 7000000},
}}})
menu[1].action()
local reviewed = marked.events[#marked.events]
t.assertEqual(reviewed.name, "review", "a duplicate covered by a mark opens review through the router")
t.assertEqual(reviewed.args[1], copy, "duplicate review focuses the enclosing marked item")
t.expect(not Keeps:valid("worktree:/Users/test/.."), "Keep refuses a worktree traversal at the end of a path")
marked.env:dispose()
for name, keys in pairs(modelKeys) do
	for key in pairs(require("apps.diskmap.models." .. name)) do t.expect(keys[key], name .. " gains no module state: " .. tostring(key)) end
end
os.exit(t.summary() and 0 or 1)
