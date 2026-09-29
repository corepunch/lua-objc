-- demo/ledger: money formatting, chart periods and the dashboard window.
_G.__headless = true

local t = require("TestKit")
local Model = require("demo.ledger.Model")
local Controller = require("demo.ledger.Controller")

t.assertEqual(Model.money(24180.52), "$24,180.52", "money groups thousands and keeps cents")
t.assertEqual(Model.money(8420), "$8,420", "whole thousands drop their cents")
t.assertEqual(Model.money(-6.5, true), "−$6.50", "spending carries a minus sign")
t.assertEqual(Model.money(4210, true), "+$4,210", "income carries a plus sign when signed")
t.assertEqual(Model.money(0), "$0.00", "zero keeps its cents")

local model = Model.new()
local chart = model:chart()
t.assertEqual(#chart.bars, 12, "the chart starts weekly")
local tallest = 0
for _, bar in ipairs(chart.bars) do tallest = math.max(tallest, bar.share) end
t.assertEqual(tallest, 1, "the tallest bar fills the plot")
t.expect(chart.bars[12].current and not chart.bars[1].current, "only the current period is highlighted")
model:setPeriod("monthly")
t.assertEqual(#model:chart().bars, 6, "monthly shows six months")
model:setPeriod("hourly")
t.assertEqual(model.period, "monthly", "an unknown period is ignored")
local shares = 0
for _, row in ipairs(model:breakdown()) do shares = shares + row.share end
t.assertEqual(shares, 100, "the category breakdown adds up")
t.assertEqual(model:transactions()[2].category, "Income", "income rows name themselves")

local controller = Controller.new()
controller:createWindow()
for _, id in ipairs({ "cards", "chart", "bars", "breakdown", "transactions" }) do
	t.expect(controller.content.refs[id] ~= nil, "the overview has #" .. id .. " for reel captures")
end
controller:setPeriod("monthly")
t.assertEqual(controller.model.period, "monthly", "the period picker reaches the model")

os.exit(t.summary() and 0 or 1)
