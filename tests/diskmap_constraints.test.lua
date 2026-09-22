_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Inspector = require("apps.diskmap.models.Inspector")
local InspectorController = require("apps.diskmap.controllers.InspectorController")
local Simulators = require("apps.diskmap.models.Simulators")

local model = Model.new("/Users/test")
local row = model.resources:find("derived")
model.measurements.derived = {bytes = 2e9, status = "complete"}
t.expect(row:validateTrash(), "complete positive trash resource validates")
local ok, err = Cleanup.moveToTrash(model, "unknown", {trash = function() error("must not run") end})
t.assertEqual(ok, false, "unknown resource cannot mutate")
t.assertEqual(err.code, "unknown_resource", "unknown resource has a stable code")

local function invalid(status, code)
	model.measurements.derived = {bytes = 2e9, status = status}
	local valid, result = row:validateTrash()
	t.assertEqual(valid, false, "status " .. status .. " cannot authorize Trash")
	t.assertEqual(result.code, code, "status " .. status .. " returns a stable code")
end
for _, status in ipairs({"partial", "failed", "denied", "excluded", "calculating"}) do invalid(status, "measurement_incomplete") end
model.measurements.derived = {bytes = 0, status = "complete"}
local zeroValid, zeroError = row:validateTrash()
t.assertEqual(zeroValid, false, "zero allocation cannot authorize Trash")
t.assertEqual(zeroError.code, "measurement_nonpositive", "zero allocation has a stable code")
model.measurements.derived = {bytes = 2e9, status = "complete"}
local savedPath = row.path
row.path = "relative/path"; t.assertEqual(row.path, "relative/path", "test changes canonical path"); invalid("complete", "invalid_path"); row.path = savedPath
local savedAction = row.action
row.action = "finder"; invalid("complete", "invalid_action"); row.action = savedAction
model.kept.xcode = true; invalid("complete", "kept_resource"); model.kept.xcode = nil
local group = model.resources:find("developer")
local groupValid, groupErr = group:validateTrash()
t.assertEqual(groupValid, false, "groups cannot be moved to Trash")
t.assertEqual(groupErr.code, "not_leaf", "group validation is named")

local calls = 0
local service = {trash = function(path) calls = calls + 1; t.assertEqual(path, savedPath, "mutation uses the current canonical path"); return true end}
local moved, moveError = Cleanup.moveToTrash(model, "derived", service)
t.assertEqual(moved, true, "valid model mutation reaches the service")
t.assertEqual(moveError, nil, "valid mutation has no error")
t.assertEqual(calls, 1, "valid mutation runs exactly once")
model.measurements.derived = {bytes = 2e9, status = "complete"}
local failedMove, failedError = Cleanup.moveToTrash(model, "derived", {trash = function() return false, "symbolic link" end})
t.assertEqual(failedMove, false, "service rejection is not reported as success")
t.assertEqual(failedError.code, "trash_service", "service failure is named")
t.assertEqual(model.measurements.derived.bytes, 2e9, "service failure preserves measurement state")

local refreshes, controllerCalls, errors = 0, 0, 0
local controller = InspectorController.new(model, {
	confirmTrash = function()
		model.kept.xcode = true
		return true
	end,
	trash = function() controllerCalls = controllerCalls + 1; return true end,
	showError = function() errors = errors + 1 end,
}, function() refreshes = refreshes + 1 end)
model.kept.xcode = nil; controller:select("derived")
t.expect(not controller:manage(), "changed Keep after confirmation blocks IO")
t.assertEqual(controllerCalls, 0, "stale confirmation never reaches IO")
t.assertEqual(errors, 1, "stale mutation reports a structured service error")
model.kept.xcode = nil
local details = Inspector.details(model, "derived")
t.expect(details.canManage, "inspector uses current trash constraints")

local validUuid = "12345678-ABCD-1234-ABCD-123456789ABC"
local simulator = {id = validUuid, name = "Test", available = true, running = false}
local simulatorOk = Simulators.validate("erase", simulator)
t.assertEqual(simulatorOk, true, "supported simulator action validates")
local _, simulatorError = Simulators.validate("format", simulator)
t.assertEqual(simulatorError.code, "unsupported_action", "unsupported simulator action is named")
_, simulatorError = Simulators.validate("delete", {id = "all", available = true, running = false})
t.assertEqual(simulatorError.code, "invalid_uuid", "simulator wildcard is rejected")
_, simulatorError = Simulators.validate("delete", {id = validUuid, available = true, running = true})
t.assertEqual(simulatorError.code, "device_running", "running simulator is rejected")
_, simulatorError = Simulators.validate("erase", {id = validUuid, available = false, running = false})
t.assertEqual(simulatorError.code, "device_unavailable", "unavailable simulator cannot be erased")
model.kept.simulators = true
_, simulatorError = Simulators.validate("delete", simulator, model)
t.assertEqual(simulatorError.code, "kept_resource", "catalog Keep protects simulator actions")

os.exit(t.summary() and 0 or 1)
