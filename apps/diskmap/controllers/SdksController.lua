local ns = require("AppKit")
local xml = require("ui.xml")
local Sdks = require("apps.diskmap.models.Sdks")
local Controller = {}; Controller.__index = Controller
function Controller.new(model, service)
	return setmetatable({model = model, service = service, generation = 0, rows = {}, query = ""}, Controller)
end
function Controller:close()
	self.generation = self.generation + 1
	if self.sheet then ns.dismiss(self.sheet); self.sheet = nil end
	if self.scope then self.scope:close(); self.scope = nil end
	self.refs = nil
end
function Controller:show()
	if not self.refs then return end
	local rows = Sdks.filter(self.rows, self.query)
	self.refs.rows:replaceRows(rows)
	self.refs.status.text = #rows == 0 and "No matching SDKs." or (#rows .. " SDKs · sizes are the SDK bundles inside this installation, already included in its total.")
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
	self.scope = ns.Scope.new()
	ns.Scope.withScope(self.scope, function()
		self.sheet, self.refs = xml.renderFile("apps/diskmap/views/Sdks.etlua", {
			title = row.name, actions = {
				search = function(value) self.query = value or ""; self:show() end,
				done = function() self:close() end,
			},
		}, ns)
		self.refs.done.keyEquivalent = "\r"
		self.sheet.defaultButtonCell = self.refs.done.cell
	end)
	ns.presentSheet(self.sheet, parent); ns.focus(self.sheet, self.refs.search); self:load()
end
return Controller
