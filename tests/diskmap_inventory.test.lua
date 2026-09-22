local Categories = require("apps.diskmap.models.Categories")
local Preferences = require("apps.diskmap.models.Preferences")
local Cleanup = require("apps.diskmap.models.Cleanup")
_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Inventory = require("apps.diskmap.models.Inventory")
local System = require("apps.diskmap.services.System")
local model = Model.new("/Users/test")
local paths, ids, exclusions = Inventory.plan(model)
t.assertEqual(#paths, #ids, "every path has one ledger owner")
t.expect(#exclusions > #paths + 3, "excluded media roots also stay out of residual traversal")
local index = {}; for i, id in ipairs(ids) do index[id] = i end
local result = {trees = {}, rootStates = {}, visited = 123, seconds = 2, errors = 1, issues = {{path = "/denied", reason = "Denied"}}}
for i in ipairs(ids) do result.rootStates[i] = "missing" end
result.trees[index["apps-system"]] = {kb = 100}; result.rootStates[index["apps-system"]] = "measured"
result.trees[index["user-trash"]] = {kb = 0, partial = true}; result.rootStates[index["user-trash"]] = "unreadable"
Inventory.apply(model, ids, result)
for _, row in ipairs(Categories.rows(model)) do t.expect(row.status ~= "notMeasured", "completed batch attempts " .. row.id) end
t.assertEqual(model.measurements["user-trash"].status, "partial", "zero with denied descendants remains partial")
t.assertEqual(model.scan.issues[1].path, "/denied", "current scan retains access evidence")
Inventory.apply(model, {"apps-system", "user-trash"}, {failure = "Worker stopped", trees = {{kb = 80}}, rootStates = {"measured"}})
t.assertEqual(model.measurements["apps-system"].bytes, 81920, "completed roots survive later worker failure")
t.assertEqual(model.measurements["user-trash"].status, "failed", "unfinished roots have no stale value")
Inventory.apply(model, {"apps-system"}, {rootStates = {"skipped"}})
t.assertEqual(model.measurements["apps-system"].status, "skipped", "linked location is distinct from access denial")
-- Scanner tests use tiny temporary trees, no windows or waiting.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/diskmap-inventory.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local a, b = root .. "/a", root .. "/b"
assert(os.execute("/bin/mkdir " .. System.quote(a) .. " " .. System.quote(b)))
local f = assert(io.open(a .. "/file", "w")); f:write(string.rep("x", 8192)); f:close()
assert(os.execute("/bin/ln " .. System.quote(a .. "/file") .. " " .. System.quote(b .. "/link")))
assert(os.execute("/bin/ln -s " .. System.quote(a) .. " " .. System.quote(root .. "/alias")))
local scanned = require("StorageScan").scan({a, b, root .. "/missing", root .. "/alias/file"}, {})
t.assertEqual(scanned.trees[1].kb + scanned.trees[2].kb, 8, "hard links across category roots count once")
t.assertEqual(scanned.rootStates[3], "missing", "absent locations have explicit zero evidence")
t.assertEqual(scanned.completed, 4, "native snapshot counts finished locations")
t.assertEqual(scanned.errors, 0, "missing catalog paths do not inflate permission errors")
t.assertEqual(scanned.rootStates[4], "skipped", "symlink ancestors never escape the scan boundary")
for _, path in ipairs({a .. "/file", b .. "/link", a, b, root .. "/alias", root}) do os.remove(path) end
os.exit(t.summary() and 0 or 1)
