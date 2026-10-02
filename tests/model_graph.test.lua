-- The model graph: dependencies are declared in the model's own file and the
-- graph builds only what a page needs, in order.
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
raises(function() Model.define({ id = "" }) end, "must be a name", "an id is a name")
-- A class without an id serves several models and learns which one it is.
local shared = Model.define({})
function shared.new(_, _, id) return { id = id } end
local sharedGraph = Model.graph({ classes = { one = shared, two = shared } })
t.assertEqual(sharedGraph:build({ "one", "two" }).two.id, "two", "a shared class is built for each id")
raises(function() Model.define({ id = "x", needs = { 1 } }) end, "lists model ids", "needs lists ids")

os.exit(t.summary() and 0 or 1)
