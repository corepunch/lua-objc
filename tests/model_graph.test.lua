-- The model graph: dependencies are declared in the model's own file, the
-- graph builds only what a page needs, in order, and a change marks the
-- dependents stale.
_G.__headless = true
local t = require("TestKit")
local Model = require("data.model")

local built = {}
local function define(id, needs, extra)
	local class = Model.define({ id = id, needs = needs })
	function class.new(deps, services)
		table.insert(built, id)
		local self = setmetatable({ id = id, deps = deps, services = services, invalidated = {} }, class)
		for key, value in pairs(extra or {}) do self[key] = value end
		return self
	end
	function class:invalidate(from) table.insert(self.invalidated, from) end
	return class
end
local function raises(fn, pattern, message)
	local ok, err = pcall(fn)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end

local classes = {
	scan = define("scan", {}),
	applications = define("applications", { "scan" }),
	simulatorPlan = define("simulatorPlan", { "scan" }),
	keep = define("keep", {}),
	cleanup = define("cleanup", { "scan", "applications", "simulatorPlan", "keep" }),
	unrelated = define("unrelated", {}),
}
local services = { name = "services" }
local graph = Model.graph({ classes = classes, services = services })

t.assertEqual(table.concat(graph:plan({ "cleanup" }), ","), "scan,applications,simulatorPlan,keep,cleanup",
	"dependencies come before dependents")
local models = graph:build({ "cleanup" })
t.assertEqual(table.concat(built, ","), "scan,applications,simulatorPlan,keep,cleanup", "models are built in dependency order")
t.expect(graph:get("unrelated") == nil, "launching one page builds only its models")
t.expect(models.cleanup.deps.scan == graph:get("scan"), "a model receives the instances it needs")
t.expect(models.cleanup.deps.unrelated == nil, "and nothing else")
t.expect(models.cleanup.services == services, "services are injected")
graph:build({ "applications" })
t.assertEqual(#built, 5, "a model is built once")

-- Staleness.
local notified = {}
graph:subscribe("cleanup", function(stale) table.insert(notified, "cleanup:" .. table.concat(stale, ",")) end)
graph:subscribe("keep", function() table.insert(notified, "keep") end)
graph:subscribe("unrelated", function() table.insert(notified, "unrelated") end)
local stale = graph:changed("applications")
t.assertEqual(table.concat(stale, ","), "applications,cleanup", "a change marks the model and its dependents stale")
t.assertEqual(table.concat(notified, "|"), "cleanup:applications,cleanup", "only subscribers of stale models hear of it")
t.assertEqual(#graph:get("cleanup").invalidated, 1, "a stale dependent is invalidated")
t.assertEqual(graph:get("cleanup").invalidated[1], "applications", "with the model that changed")
t.assertEqual(#graph:get("applications").invalidated, 0, "the model that changed is not invalidated")
t.assertEqual(table.concat(graph:changed("scan"), ","), "scan,applications,simulatorPlan,cleanup", "staleness is transitive")
t.assertEqual(table.concat(graph:changed("keep"), ","), "keep,cleanup", "staleness follows the graph, not the order")
t.assertEqual(table.concat(graph:changed("cleanup"), ","), "cleanup", "a leaf marks only itself")
graph:build({ "unrelated" })
t.assertEqual(table.concat(graph:changed("scan"), ","):find("unrelated"), nil, "an unrelated model stays fresh")

-- Errors.
raises(function() Model.graph({ classes = {} }):build({ "ghost" }) end, 'no model "ghost"', "an unknown model")
raises(function()
	Model.graph({ classes = { a = define("a", { "b" }), b = define("b", { "ghost" }) } }):build({ "a" })
end, 'no model "ghost"', "an unknown dependency")
raises(function()
	Model.graph({ classes = { a = define("a", { "b" }), b = define("b", { "c" }), c = define("c", { "a" }) } }):plan({ "a" })
end, "cycle a %-> b %-> c %-> a", "a cycle is reported with its path")
raises(function() Model.graph({ classes = { a = define("a", { "a" }) } }):plan({ "a" }) end, "cycle a %-> a", "a self dependency")
raises(function() Model.graph({ classes = { a = define("b", {}) } }):build({ "a" }) end, "whose id is", "registered under another id")
raises(function() Model.define({}) end, "needs an id", "define needs an id")
raises(function() Model.define({ id = "x", needs = { 1 } }) end, "lists model ids", "needs lists ids")

-- Schema check at build.
local Schema = require("data.schema")
local xml = require("ui.xml")
local schemas = Schema.directory("s", function() return '<Schema id="Page"><String id="title" /></Schema>' end, xml.parse)
local checked = define("checked", {}); checked.schema = "Page"
raises(function() Model.graph({ classes = { checked = checked }, schemas = schemas }):build({ "checked" }) end,
	"field title is missing", "a model lacking a declared field fails to build")
local good = define("good", {}, { title = "T" }); good.schema = "Page"
Model.graph({ classes = { good = good }, schemas = schemas }):build({ "good" })

os.exit(t.summary() and 0 or 1)
