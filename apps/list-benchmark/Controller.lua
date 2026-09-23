local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.list-benchmark.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new(config)
	if ns._benchmarkStart then ns._benchmarkStart() end
	config = config or {}
	local kind = config.kind or os.getenv("LUA_OBJC_BENCH_KIND") or "list"
	local count = config.count or tonumber(os.getenv("LUA_OBJC_BENCH_ROWS")) or 1000
	assert(kind == "eager" or kind == "list", "benchmark kind must be eager or list")
	assert(count == 1000 or count == 5000, "benchmark supports 1000 or 5000 rows")
	return setmetatable({ model = Model.new(count), kind = kind, count = count }, Controller)
end

function Controller:createWindow()
	local template = self.kind == "eager" and "Eager.etlua" or "List.etlua"
	local content = xml.renderFile("apps/list-benchmark/views/" .. template,
		{ items = self.model.items }, ns)
	self.window = ns.Window {
		title = "List benchmark: " .. self.kind .. " " .. self.count,
		content = content,
	}
	if ns._benchmarkScroll then ns._benchmarkScroll(self.window, self.kind, self.count) end
	return self.window
end

return Controller
