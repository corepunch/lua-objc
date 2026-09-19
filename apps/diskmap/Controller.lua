local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("apps.diskmap.Model")

local VIEWS = "apps/diskmap/views/"

local MAX_BAR_PX  = 500
local NAME_WIDTH  = 190
local SIZE_WIDTH  = 72
local ROW_HEIGHT  = 26
local BAR_HEIGHT  = 20
local INDENT_STEP = 14
local ROW_SPACING = 3

local DEPTH_COLORS = {
	[0] = "systemBlue",
	[1] = "accent",
	[2] = "systemGreen",
	[3] = "systemYellow",
	[4] = "systemRed",
}

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ content = nil, window = nil }, Controller)
end

local function makeBarRow(row)
	local depth  = row.depth
	local rootKb = math.max(row.rootKb, 1)
	local barPx  = math.max(math.floor(row.kb / rootKb * MAX_BAR_PX), 2)
	local color  = DEPTH_COLORS[math.min(depth, 4)] or "systemRed"
	local indent = depth * INDENT_STEP
	local nameW  = math.max(NAME_WIDTH - indent, 40)

	-- Name area (indent + label, fixed total width)
	local nameArea = ns.HStack {
		fixedWidth = NAME_WIDTH,
		spacing    = 0,
		alignment  = "center",
	}
	if indent > 0 then
		nameArea:add(ns.VStack { fixedWidth = indent })
	end
	nameArea:add(ns.Text { row.name, size = 12, fixedWidth = nameW })

	-- Colored bar
	local bar = ns.VStack {
		fixedWidth   = barPx,
		fixedHeight  = BAR_HEIGHT,
		cornerRadius = 5,
		background   = color,
	}

	-- Size label (right-aligned via trailing flex)
	local sizeLabel = ns.Text {
		Model.humanKb(row.kb),
		size       = 11,
		color      = "secondary",
		fixedWidth = SIZE_WIDTH,
		alignment  = "trailing",
	}

	local rowView = ns.HStack {
		fixedHeight = ROW_HEIGHT,
		spacing     = 8,
		alignment   = "center",
	}
	rowView:add(nameArea)
	rowView:add(bar)
	rowView:add(ns.VStack { flexGrow = 1 })
	rowView:add(sizeLabel)
	return rowView
end

local function makeLoadingView(msg)
	local spinner = ns.Spinner()
	ns.SpinnerStart(spinner)
	return ns.VStack {
		flexGrow  = 1,
		alignment = "center",
		ns.Spacer {},
		spinner,
		ns.Text { msg, size = 13, color = "secondary" },
		ns.Spacer {},
	}
end

local function makeBarsContent(rows)
	local stack = ns.VStack {
		spacing   = ROW_SPACING,
		alignment = "leading",
		padding   = 16,
	}
	for _, row in ipairs(rows) do
		stack:add(makeBarRow(row))
	end
	return ns.ScrollView {
		content  = stack,
		vertical = true,
		flexGrow = 1,
		fillWidth = true,
	}
end

function Controller:showView(view)
	self.content:clearContainer()
	self.content:add(view)
	self.content:layout()
end

function Controller:startScan(rootPath)
	self:showView(makeLoadingView("Scanning " .. rootPath .. " …"))
	local handle = Model.startScan(rootPath, 4)
	ns.async(function()
		ns.sleep(0.2)
		while not Model.isDone(handle) do
			ns.sleep(0.5)
		end
		local rows = Model.parseResults(handle, { 999, 12, 10, 8, 6 })
		if #rows == 0 then
			self:showView(ns.VStack {
				flexGrow  = 1,
				alignment = "center",
				ns.Text { "No data found.", color = "secondary" },
			})
			return
		end
		self:showView(makeBarsContent(rows))
	end)
end

function Controller:createWindow()
	self.content = ns.VStack { flexGrow = 1, fillWidth = true }

	local cfg = xml.renderFile(VIEWS .. "Window.etlua")
	cfg.content = self.content
	self.window = ns.Window(cfg)

	local home = os.getenv("HOME") or "/"
	self:startScan(home)
end

return Controller
