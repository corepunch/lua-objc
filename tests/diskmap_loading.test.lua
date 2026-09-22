_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
local Inventory = require("apps.diskmap.models.Inventory")
local Categories = require("apps.diskmap.models.Categories")
local Scan = require("apps.diskmap.controllers.ScanController")
local model = Model.new("/Users/test")
local _, ids = Inventory.plan(model)
model.measurements[ids[1]] = {bytes = 9e9, status = "complete"}
Inventory.begin(model, ids)
t.assertEqual(Model.total(model), 0, "refresh immediately discards old measurements")
for _, row in ipairs(Categories.rows(model)) do
	t.expect(row.calculating, "category starts calculating: " .. row.id)
	t.assertEqual(row.size, "Calculating…", "pending category never shows old bytes")
end
local first = model.tree[1]
local function belongs(id)
	local row = model.byId[id]
	while row do
		if row.id == first.id then return true end
		row = model.byId[row.parentId]
	end
end
local result = {completed = 0, total = #ids, trees = {}, rootStates = {}}
for i, id in ipairs(ids) do
	if not belongs(id) then break end
	result.completed = i; result.rootStates[i] = "missing"
end
t.expect(result.completed > 0 and result.completed < #ids, "fixture completes exactly one category")
Inventory.progress(model, ids, result)
local rows = Categories.rows(model)
t.expect(not rows[1].calculating and rows[1].size == "0 KB", "completed zero category stops spinning")
t.expect(rows[2].calculating, "unrelated pending category keeps spinning")
local filtered = Categories.rows(model, nil, first.name)
t.expect(not filtered[1].calculating, "filter preserves category completion")
Inventory.cancel(model)
for _, row in ipairs(Categories.rows(model)) do t.expect(not row.calculating, "cancel clears all pending indicators") end
t.assertEqual(model.measurements[ids[1]].bytes, 0, "cancel retains this scan's completed result")
Inventory.begin(model, ids)
Inventory.progress(model, ids, result)
Inventory.apply(model, ids, {failure = "Worker stopped"})
t.assertEqual(model.measurements[ids[1]].bytes, 0, "worker failure keeps already published fresh result")
t.assertEqual(model.measurements[ids[#ids]].status, "failed", "worker failure clears pending state")
t.assertEqual(model.measurements[ids[#ids]].bytes, nil, "worker failure cannot restore cached data")
local pending
local scanner = Scan.new(model, {
	start = function() return {} end,
	await = function(job, done, progress) pending = {done = done, progress = progress} end,
	cancel = function() end,
	diskSpace = function() return {totalKb = 100, freeKb = 50} end,
}, "/Users/test")
scanner:start()
pending.progress(result)
t.expect(not Categories.rows(model)[1].calculating, "controller applies incremental measurement")
t.expect(Categories.rows(model)[2].calculating, "controller leaves other categories pending")
scanner:cancel()
local failure = Scan.new(model, {start = function() error("No worker") end}, "/Users/test")
failure:start()
t.assertEqual(Model.total(model), 0, "start failure does not retain old measurements")
t.assertEqual(Categories.rows(model)[1].size, "Unavailable", "failed category reports unavailable rather than access denial")
t.expect(not Categories.rows(model)[2].calculating, "controller cancellation stops pending spinner")

-- Shared native cells: alignment, sizing, reuse, and shrinking remain independent of scan IO.
for _, tag in ipairs({"OutlineView", "List"}) do
	local view = xml.render('<' .. tag .. ' header="false"><Column id="name" controlSize="small"/><Column id="size" width="125" alignment="trailing" controlSize="small" loadingKey="calculating"/></' .. tag .. '>', {}, ns)
	view:replaceRows({{id = "a", name = "Applications", size = "Calculating…", calculating = true}})
	view.size = ns.Size(400, 150); view:layout(400)
	local cell = bridge._tableCell(view, 1, 0)
	t.assertEqual(cell.textField.alignment, 2, tag .. " trailing value is right aligned")
	t.expect(cell.textField.font.pointSize < 13, tag .. " uses small system font")
	t.assertEqual(cell.loadingIndicator.className, "NSProgressIndicator", tag .. " uses native spinner")
	t.expect(not cell.loadingIndicator.hidden, tag .. " pending indicator visible")
	t.expect(cell.textField.frame.size.width >= cell.textField.fittingSize.width, tag .. " loading label has room for native text insets")
	t.expect(cell.loadingIndicator.frame.size.width > 0, tag .. " spinner has native size")
	t.expect(cell.textField.frame.origin.x >= cell.loadingIndicator.frame.origin.x + cell.loadingIndicator.frame.size.width, tag .. " spinner precedes text without overlap")
	t.expect(cell.textField.frame.origin.x + cell.textField.frame.size.width <= cell.frame.size.width, tag .. " status fits the column")
	view:selectRow(0)
	view:replaceRows({{id = "a", name = "Applications", size = "1.0 GB", calculating = false}})
	cell = bridge._tableCell(view, 1, 0)
	t.expect(cell.loadingIndicator.hidden, tag .. " completed cell hides spinner")
	t.assertEqual(cell.textField.stringValue, "1.0 GB", tag .. " result replaces loading label")
	if tag == "OutlineView" then t.assertEqual(view.documentView.selectedRow, 0, "outline update preserves selection") end
	view:replaceRows({{id = "a", name = "Applications", size = "Calculating…", calculating = true}})
	t.expect(not bridge._tableCell(view, 1, 0).loadingIndicator.hidden, tag .. " repeat refresh restarts spinner")
	view:replaceRows({})
	t.assertEqual(view.rowCount, 0, tag .. " empty results remove loading cells")
end
os.exit(t.summary() and 0 or 1)
