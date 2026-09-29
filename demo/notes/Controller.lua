-- Opens the notebook: folders in the sidebar, the notes in the content
-- column and the selected note beside them on the Mac; a phone shows the
-- notes by themselves.
local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("demo.notes.Model")

local VIEWS = "demo/notes/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new(model)
	return setmetatable({model = model or Model.new()}, Controller)
end

function Controller:actions()
	return {
		search = function(query) self:search(query) end,
		selectNote = function(_, _, row) if row and row.id then self:select(row.id) end end,
		selectFolder = function() end,
	}
end

function Controller:render()
	local actions = self:actions()
	self.content:update({notes = self.model:visible(), favorites = self.model:favorites(), actions = actions})
	if self.detail then self.detail:update({note = self.model:note(), actions = actions}) end
end

function Controller:select(id)
	self.model:select(id)
	self:render()
end

function Controller:search(query)
	self.model:search(query)
	self:render()
end

function Controller:createWindow()
	local actions = self:actions()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", {actions = actions}, ns)
	self.content = Template.new(refs.content, VIEWS .. "Content.etlua", ns)
	if ns.platform == "AppKit" then
		local sidebar = xml.renderFile(VIEWS .. "Sidebar.etlua", {folders = self.model:folders(), actions = actions}, ns)
		local detail, detailRefs = xml.renderFile(VIEWS .. "Pane.etlua", {}, ns)
		config.sidebar, config.detail = sidebar, detail
		self.detail = Template.new(detailRefs.pane, VIEWS .. "Note.etlua", ns)
	end
	self:render()
	if ns.platform == "AppKit" then self.content.refs.notes:selectRow(0, false) end
	self.window = ns.Window(config)
	return self.window
end

return Controller
