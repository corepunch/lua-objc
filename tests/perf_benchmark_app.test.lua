_G.__headless = true

local t = require("TestKit")
local Controller = require("apps.list-benchmark.Controller")

for _, count in ipairs({ 1000, 5000 }) do
	local list = Controller.new { kind = "list", count = count }
	list:createWindow()
	t.assertEqual(#list.model.items, count, "benchmark model has requested rows")
	t.expect(list.window ~= nil, "native List benchmark renders")
end

local eager = Controller.new { kind = "eager", count = 1000 }
eager:createWindow()
t.expect(eager.window ~= nil, "eager benchmark renders")

os.exit(t.summary() and 0 or 1)
