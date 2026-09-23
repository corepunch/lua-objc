local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.swipe-actions.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:removeItem(index, row)
	if not self.model:removeAt(index, row.id) then return false end
	self.refs.items:removeRow(index - 1)
	return true
end

function Controller:setStackStatus(id, status)
	local item = self.model:setStackStatus(id, status)
	if not item then return false end
	local rowView = self.refs["stack_" .. id]
	rowView:clearRows()
	rowView:addRow({ title = item.title, status = item.status })
	return true
end

function Controller:createWindow()
	local config, refs = xml.renderFile("apps/swipe-actions/views/Main.etlua", {
		items = self.model.items,
		stackItems = self.model.stackItems,
		actions = {
			archive = function(index, row) self:removeItem(index, row) end,
			delete = function(index, row) self:removeItem(index, row) end,
			archiveStack = function(id) self:setStackStatus(id, "Archived") end,
			completeStack = function(id) self:setStackStatus(id, "Complete") end,
		},
	}, ns)
	self.refs = refs
	self.window = ns.Window(config)
	return self.window
end

return Controller
