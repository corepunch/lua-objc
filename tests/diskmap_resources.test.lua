_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local Model = require("data.model")
local Categories = require("apps.diskmap.helpers.Categories")

local function model()
	return {measurements = {}, kept = {}}
end
local definitions = {
	{id = "root", name = "Root", subtitle = "Root", icon = "folder", color = "blue", children = {
		{id = "group", name = "Group", subtitle = "Group", children = {
			{id = "leaf", name = "Leaf", subtitle = "Leaf", path = "/tmp/leaf"},
		}},
		{id = "empty", name = "Empty", subtitle = "Empty", children = {}},
	}},
	{id = "other", name = "Other", subtitle = "Other", path = "/tmp/other"},
}
local firstModel = Model.bind(model())
assert(Locations.seed(firstModel, definitions))
local roots, leaves = Locations:roots(), Locations:leaves()
t.assertEqual(#roots, 2, "roots preserve definition order")
t.assertEqual(roots[1].id, "root", "first root is canonical")
t.assertEqual(#leaves, 2, "empty groups are not leaves")
t.assertEqual(leaves[1].id, "leaf", "leaves preserve depth-first order")
t.assertEqual(Locations:find("leaf"):parent().id, "group", "parent resolves canonically")
t.assertEqual(Locations:find("root"):parent(), nil, "root has no parent")
t.assertEqual(#Locations:find("empty"):children(), 0, "empty group has an empty child sequence")
t.expect(Locations:find("empty"):isLeaf() == false, "empty group remains structurally distinct")
t.assertEqual(rawget(Locations:find("leaf"), "children"), nil, "rows do not expose mutable children")
t.assertEqual(rawget(Locations:find("leaf"), "parentId"), nil, "rows do not expose relation cache fields")
t.expect(firstModel.locationIndex ~= nil and #firstModel.locations == 5, "the store holds the rows and their index")
t.assertEqual(getmetatable(Locations:find("leaf")), getmetatable(Locations:find("other")), "one row metatable for every location")

local childCopy = Locations:find("group"):children()
childCopy[1] = nil
t.assertEqual(#Locations:find("group"):children(), 1, "relation sequences cannot mutate the collection")
firstModel.measurements.leaf = {bytes = 10, status = "complete"}
t.assertEqual(Locations:find("leaf"):measurement().bytes, 10, "row reads live measurements")
firstModel.measurements.leaf = {bytes = 20, status = "partial"}
t.assertEqual(Locations:find("leaf"):measurement().bytes, 20, "row sees measurement replacement")
firstModel.kept.root = true
t.expect(Locations:find("leaf"):isKept(), "row resolves inherited Keep")
firstModel.kept.root = nil
t.expect(not Locations:find("leaf"):isKept(), "row sees Keep removal")
local presentation = Categories.rows()
t.assertEqual(getmetatable(presentation[1]), nil, "presentation rows are plain tables")
t.assertEqual(presentation[1].parent, nil, "presentation rows do not leak relation methods")

local added = assert(Locations:add("group", {id = "new", name = "New", subtitle = "New", path = "/tmp/new"}))
t.assertEqual(added:parent().id, "group", "added row is attached to its requested parent")
t.assertEqual(#Locations:find("group"):children(), 2, "added row appears in existing relation reads")
t.assertEqual(Locations:find("new"), Locations:leaves()[#Locations:leaves()], "added row appears in leaf index")
local leafCount = #Locations:leaves()
local rejected, duplicate = Locations:add("group", {id = "newer", name = "Newer", subtitle = "Newer", path = "/tmp/new"})
t.assertEqual(rejected, nil, "duplicate path is rejected")
t.assertEqual(duplicate.code, "duplicate_path", "duplicate path has a stable code")
t.assertEqual(#Locations:leaves(), leafCount, "failed registration is atomic")
local _, duplicateId = Locations:add("group", {id = "new", name = "Other", subtitle = "Other", path = "/tmp/other-new"})
t.assertEqual(duplicateId.code, "duplicate_id", "duplicate id is rejected")
local _, badParent = Locations:add("leaf", {id = "bad-parent", name = "Bad", subtitle = "Bad"})
t.assertEqual(badParent.code, "parent_not_group", "leaf parents are rejected")
local _, missingParent = Locations:add("missing", {id = "missing-parent", name = "Bad", subtitle = "Bad"})
t.assertEqual(missingParent.code, "invalid_parent", "missing parents are rejected")

local function rejects(defs, code, label)
	local _, err = Locations.seed(model(), defs)
	t.assertEqual(err.code, code, label)
end
rejects({{id = "duplicate", name = "A", subtitle = "A"}, {id = "duplicate", name = "B", subtitle = "B"}}, "duplicate_id", "initial duplicate id")
rejects({{id = "a", name = "A", subtitle = "A", path = "/tmp/same"}, {id = "b", name = "B", subtitle = "B", path = "/tmp/same"}}, "duplicate_path", "initial duplicate path")
rejects({{id = "bad", name = "Bad", subtitle = "Bad", children = "not an array"}}, "malformed_definition", "malformed children")
local cycle = {id = "cycle", name = "Cycle", subtitle = "Cycle"}; cycle.children = {cycle}
rejects({cycle}, "cycle", "cyclic definition")

local secondModel = model()
assert(Locations.seed(secondModel, {{id = "root", name = "Root", subtitle = "Root", children = {}}}))
local firstRoot = Locations:find("root")
Model.bind(secondModel)
t.expect(Locations:find("root") ~= firstRoot, "identical ids do not cross stores: each store has its own rows")
t.assertEqual(#Locations:leaves(), 0, "and the bound store is the one read")
Model.bind(firstModel)
secondModel.kept.root = true
t.expect(not Locations:find("root"):isKept(), "Keep belongs to the owning store")

os.exit(t.summary() and 0 or 1)
