_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Files = require("apps.diskmap.models.Files")
local Recommendations = require("apps.diskmap.models.Recommendations")

-- Clean Up leads with actions: no summary tiles, files and apps before the
-- review inventory, and the checked inventory collapsed.
local page = Recommendations.page(function() return nil end)
t.expect(page.layout.tiles == nil, "Clean Up has no summary tiles ahead of its lists")
local order = {}
for _, section in ipairs(page.layout.sections) do table.insert(order, section.id) end
t.assertEqual(table.concat(order, ","), "section_rebuildable,section_decisions,section_context,section_checked",
	"rebuildable, then decisions, then collapsed context and checked inventory")
t.expect(page.layout.sections[3].collapsed and page.layout.sections[4].collapsed, "context and the checked inventory are collapsed by default")
t.assertEqual(Recommendations.details(nil, nil).detail, "", "an empty inspector stays compact")

-- Group recommendations agree with their children's eligibility.
local model = Model.new("/Users/test")
local function dirs(list)
	local result = {}
	for _, item in ipairs(list) do table.insert(result, {name = item[1], kb = item[2] / 1024, directory = true}) end
	return result
end
model.measurements.devices = {status = "complete", bytes = 4e9}
local function suggested(id)
	for _, row in ipairs(Cleanup.suggestions(model)) do if row.id == id then return row end end
end
model.breakdowns.devices = dirs({{"iPhone17,1 26.0 (23A341)", 4e9}})
t.assertEqual(suggested("devices"), nil, "device support holding only the newest version is not a dead-end suggestion")
t.expect(Cleanup.ineligible.devices:find("newest", 1, true), "and the reason is recorded: " .. tostring(Cleanup.ineligible.devices))
model.measurements.devices.bytes = 7e9
model.breakdowns.devices = dirs({{"iPhone17,1 26.0 (23A341)", 4e9}, {"18.6 (22G86)", 3e9}})
local devices = suggested("devices")
t.assertEqual(devices and devices.eligibleBytes, 3e9, "an older version is eligible; the newest is not")
t.assertEqual(devices and devices.bytes, 7e9, "bytes to review stay the measured total")

-- Simulators: eligible bytes are the minimal device set's removal, not the group.
model.measurements.simulators = {status = "complete", bytes = 22e9}
local sim = suggested("simulators")
t.assertEqual(sim.eligibleBytes, nil, "without a plan, simulator recovery is unknown, not the group total")
model.simulatorPlan = {removalBytes = 13e9, removalCount = 3, blockedBytes = 4e9, complete = true}
sim = suggested("simulators")
t.assertEqual(sim.eligibleBytes, 13e9, "with a plan, only the redundant devices count")
model.simulatorPlan = {removalBytes = 0, removalCount = 0, blockedBytes = 0, complete = true}
t.assertEqual(suggested("simulators"), nil, "a plan that removes nothing is not a suggestion")
model.simulatorPlan = nil

-- Ranking: eligible bytes x confidence / effort; unknown eligibility ranks by a fraction of its size.
local rebuildable = {bytes = 5e9, eligibleBytes = 5e9, confidence = "High", effort = "Low"}
local review = {bytes = 50e9, confidence = "Low", effort = "High"}
t.assertEqual(Cleanup.score(rebuildable), 5e9, "a proven rebuildable cache scores its size")
t.expect(Cleanup.score(review) < Cleanup.score(rebuildable), "50 GB to review does not outrank 5 GB that is certain")
t.expect(Cleanup.score({bytes = 10e9, eligibleBytes = 10e9, confidence = "Medium", effort = "Low"}) > Cleanup.score(rebuildable),
	"more recoverable bytes outrank fewer even at lower confidence")

-- Presentation separates review bytes from recoverable bytes and exposes the accounting.
model.measurements.simulators = {status = "complete", bytes = 22e9}
model.simulatorPlan = {removalBytes = 13e9, removalCount = 3, blockedBytes = 0, complete = true}
local data = Recommendations.presentation(model, "", {})
local row
for _, item in ipairs(data.decisions) do if item.id == "simulators" then row = item end end
t.expect(row and row.page == "simulators", "the simulator suggestion opens the minimal device set")
t.expect(row.subtitle:find("Keep one iPhone and one iPad", 1, true), "and says what it proposes")
t.assertEqual(data.eligibleBytes, 13e9 + 3e9, "the page total adds eligible bytes only: " .. tostring(data.eligibleBytes))
t.expect(data.reviewBytes >= 22e9, "bytes to review are reported separately")
t.expect(Recommendations.recovery(row):find("Estimated recoverable 13", 1, true), "the inspector shows estimated recoverable bytes")
t.expect(Recommendations.recovery({bytes = 9e9}):find("recoverable space is unknown", 1, true), "unknown eligibility says so")
t.expect(data.summary:find("estimated recoverable", 1, true) and data.summary:find("to review", 1, true), "the headline keeps the two apart")

-- Applications: unknown usage never reaches Clean Up; high-confidence leftovers are the eligible part.
local Applications = require("apps.diskmap.models.Applications")
local summary = Applications.summary({{appBytes = 1e9, dataBytes = 0, bytes = 1e9, usageUnknown = true}}, {
	{bytes = 3e9, tier = "high"}, {bytes = 2e9, tier = "low"}})
t.assertEqual(summary.unused, 0, "an app with unknown usage is not unused")
t.assertEqual(summary.leftoversHighBytes, 3e9, "only high-confidence leftovers are eligible")
t.assertEqual(summary.leftoverBytes, 5e9, "all leftovers are bytes to review")
local out = Recommendations.presentation(Model.new("/Users/test"), "", {apps = summary})
local leftovers
for _, item in ipairs(out.decisions) do if item.id == "leftovers" then leftovers = item end end
t.assertEqual(leftovers and leftovers.eligibleBytes, 3e9, "Clean Up carries the eligible part")
for _, item in ipairs(out.decisions) do t.expect(item.id ~= "unused-apps", "no inactivity suggestion from unknown usage") end

-- File kinds: the installer inventory is separate from what could be removed.
local Mock = require("apps.diskmap.services.Mock")
local AppController = require("apps.diskmap.Controller")
local app = AppController.new(Mock.new())
app.scan:start()
local all, removable = 0, 0
for _, row in ipairs(Files.rows(app.model, "All")) do
	if row.kindId == "installers" or row.kindId == "archives" then all = all + 1 end
end
for _, row in ipairs(Files.rows(app.model, "Installers & archives")) do
	removable = removable + 1
	t.expect(row.trashable, "the installers filter lists only files this app can move to the Trash: " .. row.path)
end
t.expect(removable > 0 and removable <= all, "removable installers are a subset of the installer-kind files")
local kinds = Files.kinds(app.model)
local installerKind
for _, kind in ipairs(kinds) do if kind.id == "installers" then installerKind = kind end end
t.expect(installerKind and installerKind.subtitle:find("inventory total", 1, true), "the File Types row calls its total an inventory")
t.expect(installerKind.removableBytes and installerKind.removableBytes <= installerKind.bytes, "and shows the removable part apart from it")
os.exit(t.summary() and 0 or 1)
