_G.__headless = true
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local Cleanup = require("apps.diskmap.helpers.Cleanup")
local Inspector = require("apps.diskmap.helpers.Inspector")
local Manage = require("apps.diskmap.flows.Manage")

local model = Store.new("/Users/test")
local row = Locations:find("user-trash")
t.expect(row ~= nil, "trash leaf is registered")
t.assertEqual(row.action, "empty", "trash leaf authorizes emptying")

model.measurements["user-trash"] = {bytes = 4e9, status = "complete"}
t.expect(row:validateEmpty(), "complete positive trash measurement validates")
local details = Inspector.details("user-trash")
t.assertEqual(details.manageTitle, "Empty Trash…", "inspector offers emptying")
t.expect(details.canManage, "inspector enables emptying for measured trash")

model.measurements["user-trash"] = {bytes = 0, status = "complete"}
local zeroValid, zeroError = row:validateEmpty()
t.assertEqual(zeroValid, false, "empty trash cannot be emptied again")
t.assertEqual(zeroError.code, "measurement_nonpositive", "empty trash has a stable code")
t.expect(not Inspector.details("user-trash").canManage, "inspector disables emptying for empty trash")

model.measurements["user-trash"] = {bytes = 4e9, status = "partial"}
local partialValid, partialError = row:validateEmpty()
t.assertEqual(partialValid, false, "partial measurement cannot authorize emptying")
t.assertEqual(partialError.code, "measurement_incomplete", "partial measurement has a stable code")

model.measurements["user-trash"] = {bytes = 4e9, status = "complete"}
model.kept.trash = true
local keptValid, keptError = row:validateEmpty()
t.assertEqual(keptValid, false, "kept trash cannot be emptied")
t.assertEqual(keptError.code, "kept_resource", "kept trash has a stable code")
model.kept.trash = nil

local calls = 0
local emptied, emptyError = Cleanup.emptyTrash("user-trash", {emptyTrash = function() calls = calls + 1; return true end})
t.assertEqual(emptied, true, "valid emptying reaches the service")
t.assertEqual(emptyError, nil, "valid emptying has no error")
t.assertEqual(calls, 1, "valid emptying runs exactly once")
local rejected, rejectedError = Cleanup.emptyTrash("user-trash", {emptyTrash = function() return false, "locked" end})
t.assertEqual(rejected, false, "service rejection is not reported as success")
t.assertEqual(rejectedError.code, "empty_service", "service failure is named")
local unknown, unknownError = Cleanup.emptyTrash("missing", {emptyTrash = function() error("must not run") end})
t.assertEqual(unknown, false, "unknown resource cannot mutate")
t.assertEqual(unknownError.code, "unknown_resource", "unknown resource has a stable code")

local confirmed = 0
local refreshes = 0
local service = {
	confirmEmptyTrash = function(confirmedRow, size)
		confirmed = confirmed + 1
		t.assertEqual(confirmedRow.id, "user-trash", "confirmation names the trash resource")
		t.expect(size:find("GB") ~= nil, "confirmation shows the measured size")
		return true
	end,
	emptyTrash = function() calls = calls + 1; return true end,
	showError = function() error("must not fail") end,
}
local controller = Manage({app = {service = service, rescan = function() refreshes = refreshes + 1 end}})
t.expect(controller:manage("user-trash"), "confirmed emptying succeeds")
t.assertEqual(confirmed, 1, "controller confirms before emptying")
t.assertEqual(calls, 2, "confirmed emptying reaches the service")
t.assertEqual(refreshes, 1, "confirmed emptying refreshes measurements")

local serviceCalls = 0
local denied = Manage({app = {service = {
	confirmEmptyTrash = function() return false end,
	emptyTrash = function() serviceCalls = serviceCalls + 1; return true end,
	showError = function() error("must not fail") end,
}, rescan = function() error("must not refresh") end}})
t.assertEqual(denied:manage("user-trash"), false, "cancelled emptying reports cancellation")
t.assertEqual(serviceCalls, 0, "cancelled emptying never reaches IO")

os.exit(t.summary() and 0 or 1)
