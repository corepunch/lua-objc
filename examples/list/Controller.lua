local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.list.Model")

local VIEWS = "examples/list/views/"

local function buildEmployeeList()
	return ns.List {
		fixedWidth = 320,
		flexGrow = 0,
		style = "fullWidth",
		header = false,
		alternatingRows = false,
		columns = {
			{ id = "name", title = "Name" },
			{ id = "role", title = "Role" },
			{ id = "dept", title = "Department" },
		},
	}
end

local function buildDetailPane()
	return ns.VStack {
		flexGrow = 1,
	}
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		employeeList = nil,
		detailPane = nil,
		window = nil,
	}, Controller)
end

function Controller:showDetail(employee)
	self.detailPane:clearContainer()
	local view = xml.renderFile(VIEWS .. "EmployeeDetail.etlua", { employee = employee })
	self.detailPane:add(view)
	self.detailPane:layout()
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	self.employeeList = buildEmployeeList()
	self.detailPane = buildDetailPane()
	cfg.content = self.employeeList
	cfg.detail = self.detailPane

	self.employeeList:replaceRows(Model.employees)

	self.employeeList:onRowSelect(function(_, _, row)
		if row and row._id then
			self:showDetail(Model.find(row._id))
		end
	end)

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
