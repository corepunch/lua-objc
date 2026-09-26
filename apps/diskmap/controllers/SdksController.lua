local ns = require("AppKit")
local Sheet = require("apps.diskmap.Sheet")
local xml = require("ui.xml")
local Sdks = require("apps.diskmap.models.Sdks")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, service)
	return setmetatable({model = model, service = service, generation = 0, rows = {}, query = ""}, Controller)
end
function Controller:close()
	self.generation = self.generation + 1
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end
function Controller:show()
	if not self.refs then return end
	local rows = Sdks.filter(self.rows, self.query)
	self.refs.rows:replaceRows(rows)
	self.refs.status.text = #rows == 0 and "No matching SDKs." or (#rows .. (#rows == 1 and " SDK" or " SDKs"))
end
function Controller:load()
	self.rows = Sdks.discover(self.service, self.root)
	self:show()
	local paths, slots = {}, {}
	for _, row in ipairs(self.rows) do
		if row.bytes == nil then table.insert(paths, row.path); table.insert(slots, row) end
	end
	if #paths == 0 or type(self.service.measure) ~= "function" then return end
	local generation = self.generation
	self.refs.status.text = "Measuring SDKs…"
	self.service.measure(paths, function(sizes)
		if generation ~= self.generation or not self.refs then return end
		local Model = require("apps.diskmap.Model")
		for index, row in ipairs(slots) do
			row.bytes = sizes[index] or 0
			row.size = Model.size(row.bytes)
		end
		self:show()
	end)
end
function Controller:open(parent, row)
	self:close()
	self.root = row.path
	self.query = ""
	self.sheet, self.refs = Sheet.present(function()
		return xml.renderFile("apps/diskmap/views/Sdks.etlua", {
			title = row.name, actions = {
				search = function(value) self.query = value or ""; self:show() end,
				done = function() self:close() end,
			},
		}, ns)
	end, parent)
	self:load()
end
return Controller
