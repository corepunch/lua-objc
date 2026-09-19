local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("apps.diskmap.Model")

local VIEWS = "apps/diskmap/views/"

local CONTENT_W   = 808   -- window 840 minus 2×16 padding
local BAR_H       = 28
local LEVEL_GAP   = 2
local SIBLING_GAP = 1
local MIN_LABEL_W = 24
local MIN_BAR_W   = 2     -- skip bars narrower than this

local DEPTH_STYLES = {
	{ bg = "systemBlue",   fg = "white" },
	{ bg = "systemGreen",  fg = "white" },
	{ bg = "systemYellow", fg = "black" },
	{ bg = "systemOrange", fg = "black" },
	{ bg = "systemRed",    fg = "white" },
	{ bg = "systemPurple", fg = "white" },
}

local function barStyle(depth)
	return DEPTH_STYLES[(depth % #DEPTH_STYLES) + 1]
end

local function makeIcicle(node, availW, depth, onSelect)
	if availW < MIN_BAR_W then return nil end

	local style = barStyle(depth)

	local bar = ns.HStack {
		fixedWidth    = availW,
		fixedHeight   = BAR_H,
		cornerRadius  = 3,
		background    = style.bg,
		alignment     = "center",
		clipsToBounds  = true,
		onDoubleClick  = function() onSelect(node.path) end,
		hoverTooltip  = { title = node.name, detail = Model.humanKb(node.kb) },
	}
	if availW >= MIN_LABEL_W then
		bar:add(ns.Text {
			node.name,
			size       = 11,
			weight     = "semibold",
			color      = style.fg,
			fixedWidth = availW - 8,
			alignment  = "center",
			lineLimit  = 1,
		})
	end

	local nodeV = ns.VStack {
		fixedWidth = availW,
		spacing    = LEVEL_GAP,
		alignment  = "leading",
	}
	nodeV:add(bar)

	if #node.children == 0 then return nodeV end

	local nodeKb = math.max(node.kb, 1)

	local row = ns.HStack {
		fixedWidth = availW,
		spacing    = 0,
		alignment  = "top",
	}

	local budget = availW
	local count  = 0
	for _, child in ipairs(node.children) do
		if budget <= 0 then break end
		local w = math.floor(child.kb / nodeKb * availW)
		if w < MIN_BAR_W then break end
		w = math.min(w, budget)
		if count > 0 then
			budget = budget - SIBLING_GAP
			if budget <= 0 then break end
			row:add(ns.VStack { fixedWidth = SIBLING_GAP, fixedHeight = BAR_H })
		end
		local cv = makeIcicle(child, w, depth + 1, onSelect)
		if cv then
			row:add(cv)
			budget = budget - w
			count  = count + 1
		end
	end
	-- "Other" filler: files + omitted small subdirs
	if budget >= MIN_BAR_W then
		if count > 0 then
			budget = budget - SIBLING_GAP
			row:add(ns.VStack { fixedWidth = SIBLING_GAP, fixedHeight = BAR_H })
		end
		if budget > 0 then
			row:add(ns.VStack {
				fixedWidth   = budget,
				fixedHeight  = BAR_H,
				cornerRadius = 3,
				background   = "separator",
			})
		end
	end
	nodeV:add(row)

	return nodeV
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

-- ── Controller ────────────────────────────────────────────────────────────

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		content     = nil,
		window      = nil,
		backItem    = nil,
		addressItem = nil,
		history     = {},
		currentPath = nil,
	}, Controller)
end

function Controller:showView(view)
	self.content:clearContainer()
	self.content:add(view)
	self.content:layout()
end

function Controller:goBack()
	if #self.history == 0 then return end
	self:startScan(table.remove(self.history), true)
end

function Controller:startScan(rootPath, isBack)
	if not isBack and self.currentPath then
		table.insert(self.history, self.currentPath)
	end
	self.currentPath = rootPath

	-- update toolbar items if they exist
	if self.backItem then self.backItem.enabled = #self.history > 0 end
	if self.addressItem then
		local v = self.addressItem.view
		if v then v.text = rootPath end
	end

	self:showView(makeLoadingView("Scanning " .. rootPath .. " …"))

	local handle = Model.startScan(rootPath, 4)
	ns.async(function()
		ns.sleep(0.2)
		while not Model.isDone(handle) do ns.sleep(0.5) end

		local tree = Model.parseTree(handle)
		if not tree then
			self:showView(ns.VStack {
				flexGrow  = 1,
				alignment = "center",
				ns.Text { "No data found.", color = "secondary" },
			})
			return
		end

		local root = makeIcicle(tree, CONTENT_W, 0, function(path)
			self:startScan(path)
		end)
		local wrap = ns.VStack {
			spacing   = 0,
			alignment = "leading",
			padding   = 16,
		}
		wrap:add(root)
		self:showView(ns.ScrollView {
			content   = wrap,
			vertical  = true,
			flexGrow  = 1,
			fillWidth = true,
		})
	end)
end

function Controller:createWindow()
	self.content = ns.VStack { flexGrow = 1, fillWidth = true }

	local rootPath = (arg and arg[1]) or os.getenv("HOME") or "/"

	local cfg = xml.renderFile(VIEWS .. "Window.etlua")
	cfg.content   = self.content
	cfg.hideTitle = true    -- toolbar replaces the title; no text needed
	cfg.toolbar   = {
		{ id = "back",    icon = "chevron.left", tooltip = "Go Back",
		  action = function() self:goBack() end },
		{ id = "address", type = "field",  label = "Path",
		  value = rootPath, minWidth = 500,
		  onSubmit = function(path) self:startScan(path) end },
	}
	self.window = ns.Window(cfg)

	-- grab references to toolbar items for later updates
	local ok1, bi = pcall(ns.ToolbarItem, self.window, "back")
	local ok2, ai = pcall(ns.ToolbarItem, self.window, "address")
	self.backItem    = ok1 and bi or nil
	self.addressItem = ok2 and ai or nil

	self:startScan(rootPath)
end

return Controller
