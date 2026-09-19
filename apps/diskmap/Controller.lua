local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("apps.diskmap.Model")

local VIEWS = "apps/diskmap/views/"

-- ── Chart constants ──────────────────────────────────────────────────────

local BAR_H       = 28
local LEVEL_GAP   = 2
local SIBLING_GAP = 1
local MIN_LABEL_W = 50
local MIN_BAR_W   = 2

local DEPTH_STYLES = {
	{ bg = "systemBlue",   fg = "white" },
	{ bg = "systemGreen",  fg = "white" },
	{ bg = "systemOrange", fg = "black" },
	{ bg = "systemPurple", fg = "white" },
	{ bg = "systemRed",    fg = "white" },
	{ bg = "systemTeal",   fg = "white" },
}

local function barStyle(depth)
	return DEPTH_STYLES[(depth % #DEPTH_STYLES) + 1]
end

-- Folder names that typically contain regenerable/cleanable content
local CLEANABLE = {
	["build"]         = "build artifacts — can be rebuilt",
	["dist"]          = "build output — can be rebuilt",
	["out"]           = "build output — can be rebuilt",
	["node_modules"]  = "npm packages — reinstall with npm install",
	[".cache"]        = "cache files — safe to delete",
	["__pycache__"]   = "Python bytecode cache",
	["vendor"]        = "vendored dependencies — reinstallable",
	["Pods"]          = "CocoaPods — reinstall with pod install",
	["DerivedData"]   = "Xcode build data — safe to delete",
	[".next"]         = "Next.js cache — rebuilt on next build",
	["target"]        = "build output — can be rebuilt",
	[".gradle"]       = "Gradle cache — rebuilt on next build",
	["xcuserdata"]    = "Xcode user data — safe to delete",
	[".lmstudio"]     = "LLM models — delete unused models in LM Studio",
	[".ollama"]       = "Ollama models — remove with: ollama rm <model>",
	[".codex"]        = "OpenAI Codex data — safe to delete",
	["Downloads"]     = "downloads — likely contains stale installers",
}

-- ── Context menu ─────────────────────────────────────────────────────────

local function makeContextMenuItems(ctrl, node)
	return function()
		return {
			{ title = "Reveal in Finder", systemImage = "folder",
			  action = function() ns.revealInFinder(node.path) end },
			{ title = "Open", systemImage = "arrow.up.forward.square",
			  action = function() ns.openPath(node.path) end },
			{ title = "Copy Path", systemImage = "doc.on.doc",
			  action = function() ns.copyToClipboard(node.path) end },
			{ separator = true },
			{ title = "Move to Trash", systemImage = "trash",
			  action = function() ctrl:trashPath(node.path, node.name, node.kb) end },
		}
	end
end

-- ── Icicle chart ─────────────────────────────────────────────────────────

local function makeIcicle(node, availW, depth, ctrl)
	if availW < MIN_BAR_W then return nil end

	local style = barStyle(depth)
	local sizeStr = Model.humanKb(node.kb)
	local labelText = node.name .. "  " .. sizeStr

	local bar = ns.HStack {
		fixedWidth    = availW,
		fixedHeight   = BAR_H,
		cornerRadius  = 3,
		background    = style.bg,
		alignment     = "center",
		clipsToBounds = true,
		onClick       = function() ctrl:selectNode(node) end,
		onDoubleClick = function() ctrl:startScan(node.path) end,
		contextMenu   = makeContextMenuItems(ctrl, node),
		hoverTooltip  = { title = node.name, detail = sizeStr },
	}
	if availW >= MIN_LABEL_W then
		bar:add(ns.Text {
			labelText,
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
		local cv = makeIcicle(child, w, depth + 1, ctrl)
		if cv then
			row:add(cv)
			budget = budget - w
			count  = count + 1
		end
	end
	if budget >= MIN_BAR_W then
		if count > 0 then
			budget = budget - SIBLING_GAP
			row:add(ns.VStack { fixedWidth = SIBLING_GAP, fixedHeight = BAR_H })
		end
		if budget > 0 then
			row:add(ns.HStack {
				fixedWidth   = budget,
				fixedHeight  = BAR_H,
				cornerRadius = 3,
				background   = "separator",
				alignment    = "center",
				clipsToBounds = true,
				hoverTooltip = { title = "Other", detail = "Files and small folders" },
			})
		end
	end
	nodeV:add(row)

	return nodeV
end

-- ── Loading / empty views ────────────────────────────────────────────────

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

local function makeEmptyView(msg)
	return ns.VStack {
		flexGrow  = 1,
		alignment = "center",
		ns.Spacer {},
		ns.Text { msg or "No data found.", size = 14, color = "secondary" },
		ns.Spacer {},
	}
end

-- ── Suggestions section ──────────────────────────────────────────────────

local function buildSuggestions(tree)
	local items = {}
	for _, child in ipairs(tree.children) do
		local hint = CLEANABLE[child.name]
		if hint then
			items[#items + 1] = {
				node = child,
				hint = hint,
			}
		end
	end
	table.sort(items, function(a, b) return a.node.kb > b.node.kb end)
	return items
end

local function makeSuggestionsView(suggestions, ctrl)
	if #suggestions == 0 then return nil end

	local list = ns.VStack {
		fillWidth = true,
		spacing   = 2,
		alignment = "leading",
	}
	for _, s in ipairs(suggestions) do
		local row = ns.HStack {
			fillWidth = true,
			spacing   = 8,
			padding   = 6,
			paddingHorizontal = 12,
			alignment = "center",
			cornerRadius = 5,
			background   = "controlBackground",
			contextMenu  = makeContextMenuItems(ctrl, s.node),
			onDoubleClick = function() ctrl:startScan(s.node.path) end,
			ns.Text { s.node.name, size = 12, weight = "semibold" },
			ns.Text { Model.humanKb(s.node.kb), size = 11, weight = "medium", color = "secondary" },
			ns.Text { s.hint, size = 11, color = "secondary" },
			ns.Spacer {},
			ns.Button {
				title = "Reveal",
				style = "plain",
				action = function() ns.revealInFinder(s.node.path) end,
			},
		}
		list:add(row)
	end

	return ns.VStack {
		fillWidth = true,
		spacing   = 6,
		alignment = "leading",
		ns.Text { "Suggestions", size = 12, weight = "bold", color = "secondary" },
		list,
	}
end

-- ── Children table ───────────────────────────────────────────────────────

local function makeChildrenTable(tree, ctrl)
	if #tree.children == 0 then return nil end

	local parentKb = math.max(tree.kb, 1)
	local rows = {}
	for _, child in ipairs(tree.children) do
		rows[#rows + 1] = {
			name  = child.name,
			size  = Model.humanKb(child.kb),
			pct   = string.format("%.1f%%", child.kb / parentKb * 100),
			items = tostring(#child.children),
			path  = child.path,
			node  = child,
		}
	end

	local list = ns.List {
		columns = {
			{ id = "name",  title = "Name",  minWidth = 120 },
			{ id = "size",  title = "Size",  width = 80, alignment = "right" },
			{ id = "pct",   title = "%",     width = 60, alignment = "right" },
			{ id = "items", title = "Items", width = 55, alignment = "right" },
		},
		data   = rows,
		style  = "inset",
		header = true,
		alternatingRows = true,
		fillWidth  = true,
		fixedHeight = math.min(#rows * 24 + 28, 300),
		onSelect = function(_, idx, row)
			if row and row.node then ctrl:selectNode(row.node) end
		end,
		onActivate = function(_, idx, row)
			if row and row.path then ctrl:startScan(row.path) end
		end,
	}

	return ns.VStack {
		fillWidth = true,
		spacing   = 6,
		alignment = "leading",
		ns.Text { "Contents", size = 12, weight = "bold", color = "secondary" },
		list,
	}
end

-- ── Selected item detail ─────────────────────────────────────────────────

local function makeSelectionDetail(node, parentKb)
	if not node then return nil end
	local pct = parentKb > 0
		and string.format("%.1f%%", node.kb / parentKb * 100) or "—"
	return ns.HStack {
		fillWidth   = true,
		fixedHeight = 32,
		padding     = 12,
		spacing     = 16,
		alignment   = "center",
		background  = "controlBackground",
		cornerRadius = 6,
		contextMenu  = makeContextMenuItems({ trashPath = function() end, startScan = function() end }, node),
		ns.Text { node.name, size = 12, weight = "semibold" },
		ns.Text { node.path, size = 11, color = "secondary", lineLimit = 1 },
		ns.Spacer {},
		ns.Text { Model.humanKb(node.kb), size = 12 },
		ns.Text { pct, size = 12, color = "secondary" },
		ns.Text { #node.children .. " sub-folders", size = 11, color = "tertiary" },
	}
end

-- ── Status bar ───────────────────────────────────────────────────────────

local function makeStatusBar(tree, diskInfo)
	local parts = {}
	parts[#parts + 1] = "Total: " .. Model.humanKb(tree.kb)
	parts[#parts + 1] = tostring(#tree.children) .. " items"
	if diskInfo then
		parts[#parts + 1] = "Free: " .. Model.humanKb(diskInfo.freeKb)
	end
	return ns.HStack {
		fillWidth   = true,
		fixedHeight = 22,
		padding     = 8,
		alignment   = "center",
		ns.Text {
			table.concat(parts, "   ·   "),
			size  = 11,
			color = "secondary",
		},
	}
end

-- ── Controller ───────────────────────────────────────────────────────────

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		window       = nil,
		contentArea  = nil,
		backItem     = nil,
		forwardItem  = nil,
		addressItem  = nil,
		history      = {},
		forward      = {},
		currentPath  = nil,
		currentTree  = nil,
		selectedNode = nil,
		chartWidth   = 760,
		nodeCache    = {},
	}, Controller)
end

function Controller:cacheNodes(node)
	self.nodeCache[node.path] = node
	for _, child in ipairs(node.children) do
		self:cacheNodes(child)
	end
end

function Controller:selectNode(node)
	self.selectedNode = node
end

function Controller:goBack()
	if #self.history == 0 then return end
	table.insert(self.forward, self.currentPath)
	self:startScan(table.remove(self.history), true)
end

function Controller:goForward()
	if #self.forward == 0 then return end
	table.insert(self.history, self.currentPath)
	self:startScan(table.remove(self.forward), true)
end

function Controller:goUp()
	if not self.currentPath then return end
	local parent = self.currentPath:match("^(.+)/[^/]+$")
	if parent and parent ~= "" then
		self:startScan(parent)
	end
end

function Controller:trashPath(path, name, kb)
	local choice = ns.Alert {
		title = "Move to Trash?",
		message = string.format(
			'"%s" (%s) will be moved to the Trash.',
			name, Model.humanKb(kb)),
		buttons = { "Move to Trash", "Cancel" },
	}
	if choice == 1 then
		local ok, err = ns.moveToTrash(path)
		if ok then
			self:rescan()
		else
			ns.Alert {
				title = "Could not move to Trash",
				message = err or "Unknown error",
				buttons = { "OK" },
			}
		end
	end
end

function Controller:updateToolbar()
	if self.backItem then
		self.backItem.enabled = #self.history > 0
	end
	if self.forwardItem then
		self.forwardItem.enabled = #self.forward > 0
	end
	if self.addressItem then
		local v = self.addressItem.view
		if v then v.text = self.currentPath or "" end
	end
end

function Controller:showContent(view)
	self.contentArea:clearContainer()
	self.contentArea:add(view)
	self.contentArea:layout()
end

function Controller:displayTree(tree)
	self.currentTree = tree
	local diskInfo = Model.diskSpace(self.currentPath)

	local stack = ns.VStack {
		spacing   = 16,
		alignment = "leading",
		padding   = 16,
		fillWidth = true,
	}

	local root = makeIcicle(tree, self.chartWidth, 0, self)
	if root then stack:add(root) end

	local suggestions = buildSuggestions(tree)
	local sugView = makeSuggestionsView(suggestions, self)
	if sugView then stack:add(sugView) end

	local childrenView = makeChildrenTable(tree, self)
	if childrenView then stack:add(childrenView) end

	stack:add(makeStatusBar(tree, diskInfo))

	self:showContent(ns.ScrollView {
		content   = stack,
		vertical  = true,
		flexGrow  = 1,
		fillWidth = true,
	})
end

function Controller:startScan(rootPath, isNav)
	if not isNav and self.currentPath then
		table.insert(self.history, self.currentPath)
		self.forward = {}
	end
	self.currentPath = rootPath
	self.selectedNode = nil
	self.currentTree = nil
	self:updateToolbar()

	-- Use cached tree if available and populated
	local cached = self.nodeCache[rootPath]
	if cached and #cached.children > 0 then
		self:displayTree(cached)
		return
	end

	self:showContent(makeLoadingView("Scanning " .. rootPath .. " …"))

	local handle = Model.startScan(rootPath, 5)
	local self_ = self
	ns.async(function()
		ns.sleep(0.2)
		while not Model.isDone(handle) do ns.sleep(0.5) end

		local tree = Model.parseTree(handle)
		if not tree then
			self_:showContent(makeEmptyView())
			return
		end

		self_:cacheNodes(tree)
		self_:displayTree(tree)
	end)
end

function Controller:rescan()
	if not self.currentPath then return end
	self.nodeCache[self.currentPath] = nil
	self:startScan(self.currentPath)
end

function Controller:createMenuBar()
	local self_ = self
	ns.MenuItem {
		menu = "File",
		title = "Reveal in Finder",
		keyEquivalent = "r",
		modifiers = { "command", "shift" },
		action = function()
			local node = self_.selectedNode
			if node then ns.revealInFinder(node.path)
			elseif self_.currentPath then ns.revealInFinder(self_.currentPath) end
		end,
	}
	ns.MenuItem {
		menu = "File",
		title = "Open",
		keyEquivalent = "o",
		modifiers = { "command" },
		action = function()
			local node = self_.selectedNode
			if node then ns.openPath(node.path)
			elseif self_.currentPath then ns.openPath(self_.currentPath) end
		end,
	}
	ns.MenuItem {
		menu = "File",
		title = "Copy Path",
		keyEquivalent = "c",
		modifiers = { "command", "shift" },
		action = function()
			local node = self_.selectedNode
			local path = node and node.path or self_.currentPath
			if path then ns.copyToClipboard(path) end
		end,
	}
	ns.MenuItem {
		menu = "File",
		title = "Move to Trash",
		keyEquivalent = "\b",
		modifiers = { "command" },
		action = function()
			local node = self_.selectedNode
			if node then self_:trashPath(node.path, node.name, node.kb) end
		end,
	}
	ns.MenuItem {
		menu = "Go",
		title = "Back",
		keyEquivalent = "[",
		modifiers = { "command" },
		action = function() self_:goBack() end,
	}
	ns.MenuItem {
		menu = "Go",
		title = "Forward",
		keyEquivalent = "]",
		modifiers = { "command" },
		action = function() self_:goForward() end,
	}
	ns.MenuItem {
		menu = "Go",
		title = "Enclosing Folder",
		keyEquivalent = "",
		modifiers = { "command" },
		action = function() self_:goUp() end,
	}
	ns.MenuItem {
		menu = "Go",
		title = "Go to Path…",
		keyEquivalent = "g",
		modifiers = { "command", "shift" },
		action = function()
			if self_.window and self_.addressItem then
				local v = self_.addressItem.view
				if v then self_.window:focus(v) end
			end
		end,
	}
	ns.MenuItem {
		menu = "View",
		title = "Rescan",
		keyEquivalent = "r",
		modifiers = { "command" },
		action = function()
			self_:rescan()
		end,
	}
end

function Controller:createWindow()
	local self_ = self

	-- Sidebar: utilities list (Settings-style)
	local sidebarList = ns.List {
		columns = {
			{ id = "name", title = "Utilities", minWidth = 140,
			  systemImage = "internaldrive" },
		},
		data = {
			{ name = "Disk Map" },
		},
		style  = "sourceList",
		header = false,
		drawsBackground = false,
		flexGrow = 1,
	}
	sidebarList:selectRow(1)

	local sidebar = ns.VStack { flexGrow = 1, fillWidth = true }
	sidebar:add(sidebarList)

	-- Content area
	self.contentArea = ns.VStack { flexGrow = 1, fillWidth = true }

	local rootPath = (arg and arg[1]) or os.getenv("HOME") or "/"

	local cfg = xml.renderFile(VIEWS .. "Window.etlua")
	local sidebarW = 180
	self.chartWidth = (cfg.width or 1060) - sidebarW - 48
	cfg.sidebar      = sidebar
	cfg.sidebarWidth = sidebarW
	cfg.content      = self.contentArea
	cfg.hideTitle    = true
	cfg.toolbar = {
		{ id = "toggleSidebar" },
		{ id = "back",    icon = "chevron.left",  tooltip = "Back",
		  action = function() self_:goBack() end },
		{ id = "forward", icon = "chevron.right", tooltip = "Forward",
		  action = function() self_:goForward() end },
		{ id = "address", type = "field", label = "Path",
		  value = rootPath, minWidth = 400,
		  onSubmit = function(path) self_:startScan(path) end },
		{ id = "rescan",  icon = "arrow.clockwise", tooltip = "Rescan",
		  action = function()
			self_:rescan()
		  end },
	}
	self.window = ns.Window(cfg)

	local ok1, bi = pcall(ns.ToolbarItem, self.window, "back")
	local ok2, fi = pcall(ns.ToolbarItem, self.window, "forward")
	local ok3, ai = pcall(ns.ToolbarItem, self.window, "address")
	self.backItem    = ok1 and bi or nil
	self.forwardItem = ok2 and fi or nil
	self.addressItem = ok3 and ai or nil

	self:createMenuBar()
	self:startScan(rootPath)
end

return Controller
