_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local SystemDetails = require("apps.diskmap.models.SystemDetails")
local Inspector = require("apps.diskmap.models.Inspector")

t.assertEqual(SystemDetails.parseSnapshots("Snapshots for disk /:\ncom.apple.TimeMachine.2026-09-20-120000.local\ncom.apple.TimeMachine.2026-09-21-120000.local\n"), 2, "two snapshots are counted")
t.assertEqual(SystemDetails.parseSnapshots("Snapshots for disk /:\n"), 0, "no snapshots count as zero")
t.assertEqual(SystemDetails.parseSnapshots("tmutil: command failed"), 0, "failure output counts as zero")
t.assertEqual(SystemDetails.parseSnapshots(nil), nil, "missing output stays unknown")

local model = Model.new("/Users/test")
model.measurements["user-caches"] = {bytes = 30e9, status = "complete"}
model.measurements["support"] = {bytes = 12e9, status = "complete"}
model.measurements["user-logs"] = {bytes = 1e9, status = "complete"}
model.measurements.vm = {bytes = 8e9, status = "complete"}
local explanation = SystemDetails.explain(model)
t.assertEqual(explanation.contributors[1].id, "user-caches", "largest contributor ranks first")
t.assertEqual(explanation.contributors[1].size, "30.0 GB", "contributor sizes use decimal gigabytes")
t.assertEqual(explanation.total.size, "43.0 GB", "decoder totals measured system data")
t.assertEqual(explanation.vm.size, "8.0 GB", "virtual memory is reported separately")
t.expect(explanation.measuredLocations >= 3, "measured location count is reported")
t.expect(explanation.knownLocations > explanation.measuredLocations, "unmeasured locations stay visible")

local text = SystemDetails.format(explanation, 2)
t.expect(text:find("43.0 GB", 1, true) ~= nil, "decoder names the measured total")
t.expect(text:find("Application caches", 1, true) ~= nil, "decoder names the largest contributor")
t.expect(text:find("2 local Time Machine snapshots", 1, true) ~= nil, "decoder names the snapshot count")
t.expect(text:find("cannot attribute", 1, true) ~= nil, "decoder states the snapshot accounting limit")
local emptyText = SystemDetails.format(explanation, 0)
t.expect(emptyText:find("No local Time Machine snapshots", 1, true) ~= nil, "zero snapshots are stated plainly")
local unknownText = SystemDetails.format(explanation, nil)
t.expect(unknownText:find("system managed", 1, true) ~= nil, "unknown snapshots stay system managed")

local details = Inspector.details(model, "system-data")
t.expect(details.text:find("43.0 GB", 1, true) ~= nil, "system-data inspector decodes the total")
t.expect(details.text:find("cannot attribute", 1, true) ~= nil, "system-data inspector states accounting limits")

local fresh = Model.new("/Users/test")
local pending = SystemDetails.format(SystemDetails.explain(fresh), nil)
t.expect(pending:find("still being measured", 1, true) ~= nil, "unmeasured inventory is not presented as zero")

os.exit(t.summary() and 0 or 1)
