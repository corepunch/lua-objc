_G.__headless = true
local t = require("TestKit")
local Resources = require("apps.diskmap.models.Resources")
local Categories = require("apps.diskmap.models.Categories")

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
local firstModel = model()
local resources = assert(Resources.new(firstModel, definitions))
firstModel.resources = resources
local roots, leaves = resources:roots(), resources:leaves()
t.assertEqual(#roots, 2, "roots preserve definition order")
t.assertEqual(roots[1].id, "root", "first root is canonical")
t.assertEqual(#leaves, 2, "empty groups are not leaves")
t.assertEqual(leaves[1].id, "leaf", "leaves preserve depth-first order")
t.assertEqual(resources:find("leaf"):getParent().id, "group", "parent resolves canonically")
t.assertEqual(resources:find("root"):getParent(), nil, "root has no parent")
t.assertEqual(#resources:find("empty"):getChildren(), 0, "empty group has an empty child sequence")
t.expect(resources:find("empty"):isLeaf() == false, "empty group remains structurally distinct")
t.assertEqual(resources:find("leaf").children, nil, "rows do not expose mutable children")
t.assertEqual(resources:find("leaf").parentId, nil, "rows do not expose relation cache fields")
t.assertEqual(resources.byId, nil, "collection indexes are private")
t.assertEqual(getmetatable(resources:find("leaf")), getmetatable(resources:find("other")), "one row metatable per collection")

local childCopy = resources:find("group"):getChildren()
childCopy[1] = nil
t.assertEqual(#resources:find("group"):getChildren(), 1, "relation sequences cannot mutate the collection")
firstModel.measurements.leaf = {bytes = 10, status = "complete"}
t.assertEqual(resources:find("leaf"):getMeasurement().bytes, 10, "row reads live measurements")
firstModel.measurements.leaf = {bytes = 20, status = "partial"}
t.assertEqual(resources:find("leaf"):getMeasurement().bytes, 20, "row sees measurement replacement")
firstModel.kept.root = true
t.expect(resources:find("leaf"):isKept(), "row resolves inherited Keep")
firstModel.kept.root = nil
t.expect(not resources:find("leaf"):isKept(), "row sees Keep removal")
local presentation = Categories.rows(firstModel)
t.assertEqual(getmetatable(presentation[1]), nil, "presentation rows are plain tables")
t.assertEqual(presentation[1].getParent, nil, "presentation rows do not leak relation methods")

local added = assert(resources:add("group", {id = "new", name = "New", subtitle = "New", path = "/tmp/new"}))
t.assertEqual(added:getParent().id, "group", "added row is attached to its requested parent")
t.assertEqual(#resources:find("group"):getChildren(), 2, "added row appears in existing relation reads")
t.assertEqual(resources:find("new"), resources:leaves()[#resources:leaves()], "added row appears in leaf index")
local leafCount = #resources:leaves()
local rejected, duplicate = resources:add("group", {id = "newer", name = "Newer", subtitle = "Newer", path = "/tmp/new"})
t.assertEqual(rejected, nil, "duplicate path is rejected")
t.assertEqual(duplicate.code, "duplicate_path", "duplicate path has a stable code")
t.assertEqual(#resources:leaves(), leafCount, "failed registration is atomic")
local _, duplicateId = resources:add("group", {id = "new", name = "Other", subtitle = "Other", path = "/tmp/other-new"})
t.assertEqual(duplicateId.code, "duplicate_id", "duplicate id is rejected")
local _, badParent = resources:add("leaf", {id = "bad-parent", name = "Bad", subtitle = "Bad"})
t.assertEqual(badParent.code, "parent_not_group", "leaf parents are rejected")
local _, missingParent = resources:add("missing", {id = "missing-parent", name = "Bad", subtitle = "Bad"})
t.assertEqual(missingParent.code, "invalid_parent", "missing parents are rejected")

local function rejects(defs, code, label)
	local _, err = Resources.new(model(), defs)
	t.assertEqual(err.code, code, label)
end
rejects({{id = "duplicate", name = "A", subtitle = "A"}, {id = "duplicate", name = "B", subtitle = "B"}}, "duplicate_id", "initial duplicate id")
rejects({{id = "a", name = "A", subtitle = "A", path = "/tmp/same"}, {id = "b", name = "B", subtitle = "B", path = "/tmp/same"}}, "duplicate_path", "initial duplicate path")
rejects({{id = "bad", name = "Bad", subtitle = "Bad", children = "not an array"}}, "malformed_definition", "malformed children")
local cycle = {id = "cycle", name = "Cycle", subtitle = "Cycle"}; cycle.children = {cycle}
rejects({cycle}, "cycle", "cyclic definition")

local secondModel = model()
local secondResources = assert(Resources.new(secondModel, {{id = "root", name = "Root", subtitle = "Root", children = {}}}))
t.expect(secondResources:find("root") ~= resources:find("root"), "identical ids do not cross model boundaries")
secondModel.kept.root = true
t.expect(not resources:find("root"):isKept(), "Keep belongs to the owning model")

os.exit(t.summary() and 0 or 1)
