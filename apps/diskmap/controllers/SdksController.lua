local ns = require("AppKit")
local Sheet = require("apps.diskmap.Sheet")
local xml = require("ui.xml")
local Schema = require("data.schema")
local Binder = require("data.binder")
local Sdks = require("apps.diskmap.models.Sdks")
local SdkList = require("apps.diskmap.models.SdkList")

-- Coordinates the SDK sheet: it starts discovery and measuring and owns the
-- sheet's lifetime. The sheet's rows, status line and search field bind to
-- `SdkList` by name (views/Sdks.etlua, schemas/SdkList.xml), so nothing here
-- copies model values into views.
local Controller = {}; Controller.__index = Controller
function Controller.new(model, service)
	return setmetatable({model = model, service = service, generation = 0, schemas = Schema.app("apps/diskmap/schemas")}, Controller)
end
function Controller:close()
	self.generation = self.generation + 1
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs, self.binder = nil, nil, nil
end
function Controller:show()
	if self.binder then self.binder:update() end
end
function Controller:load()
	self.list:setRows(Sdks.discover(self.service, self.root))
	local paths, slots = {}, {}
	for _, row in ipairs(self.list.all) do
		if row.bytes == nil then table.insert(paths, row.path); table.insert(slots, row) end
	end
	if #paths == 0 or type(self.service.measure) ~= "function" then return self:show() end
	local generation = self.generation
	self.list.measuring = true
	self:show()
	self.service.measure(paths, function(sizes)
		if generation ~= self.generation or not self.refs then return end
		for index, row in ipairs(slots) do row.bytes = sizes[index] or 0 end
		self.list.measuring = false
		self:show()
	end)
end
function Controller:open(parent, row)
	self:close()
	self.root = row.path
	self.list = SdkList.new()
	self.binder = Binder.new({schema = self.schemas("SdkList"), model = self.schemas("SdkList"):check(self.list)})
	self.sheet, self.refs = Sheet.present(function()
		return xml.renderFile("apps/diskmap/views/Sdks.etlua", {
			title = row.name, binder = self.binder, actions = {done = function() self:close() end},
		}, ns)
	end, parent)
	self:load()
end
return Controller
