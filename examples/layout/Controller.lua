local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.layout.Model")

local VIEWS = "examples/layout/views/"

local ACTIONS = {
	done = function(self) self:close() end,
}

local function buildNavList()
	return ns.List {
		fixedWidth = 170,
		flexGrow = 0,
		minWidth = 130,
		maxWidth = 240,
		style = "sourceList",
		header = false,
		alternatingRows = false,
		columns = {
			{ id = "section" },
		},
	}
end

local function buildContentList()
	return ns.List {
		flexGrow = 1,
		minWidth = 260,
		style = "fullWidth",
		header = false,
		alternatingRows = false,
		columns = {
			{ id = "item", title = "Item", width = 140 },
			{ id = "owner", title = "Owner", width = 75 },
			{ id = "status", title = "Status", width = 65 },
		},
	}
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		navList = nil,
		contentList = nil,
		window = nil,
	}, Controller)
end

function Controller:showSection(sectionId)
	local items = Model.itemsForSection(sectionId)
	if #items > 0 then
		self.contentList:replaceRows(items)
	else
		self.contentList:replaceRows({})
	end
end

function Controller:close()
	if self.window then
		self.window:close()
	end
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	self.navList = buildNavList()
	self.contentList = buildContentList()
	cfg.sidebar = self.navList
	cfg.content = self.contentList

	self.navList:replaceRows(Model.navigationItems)

	self.navList:onRowSelect(function(_, _, row)
		if row and row._id then
			self:showSection(row._id)
		end
	end)

	self:showSection("overview")

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
