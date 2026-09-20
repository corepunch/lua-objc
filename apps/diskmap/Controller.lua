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
	["build"]         = "Build artifacts — can be rebuilt",
	["dist"]          = "Build output — can be rebuilt",
	["out"]           = "Build output — can be rebuilt",
	["node_modules"]  = "npm packages — reinstall with npm install",
	[".cache"]        = "Cache files — safe to delete",
	["__pycache__"]   = "Python bytecode cache",
	["vendor"]        = "Vendored deps — reinstallable",
	["Pods"]          = "CocoaPods — reinstall with pod install",
	["DerivedData"]   = "Xcode build data — safe to delete",
	[".next"]         = "Next.js cache — rebuilt on next build",
	["target"]        = "Build output — can be rebuilt",
	[".gradle"]       = "Gradle cache — rebuilt on next build",
	["xcuserdata"]    = "Xcode user data — safe to delete",
	[".lmstudio"]     = "LLM models — delete unused in LM Studio",
	[".ollama"]       = "Ollama models — remove with: ollama rm",
	[".codex"]        = "OpenAI Codex data — safe to delete",
	["Downloads"]     = "Downloads — likely stale installers",
}

-- SF Symbol icons for known folder names
local FOLDER_ICONS = {
	["Developer"]     = "hammer.fill",
	["Library"]       = "books.vertical.fill",
	["Downloads"]     = "arrow.down.circle.fill",
	["Documents"]     = "doc.fill",
	["Desktop"]       = "menubar.dock.rectangle",
	["Applications"]  = "app.fill",
	["Movies"]        = "film.fill",
	["Music"]         = "music.note",
	["Pictures"]      = "photo.fill",
	["Photos"]        = "photo.fill",
	[".lmstudio"]     = "brain",
	[".ollama"]       = "brain.head.profile",
	[".cache"]        = "archivebox.fill",
	[".codex"]        = "terminal.fill",
	[".local"]        = "internaldrive.fill",
	[".vscode"]       = "curlybraces",
	[".claude"]       = "sparkle",
	["build"]         = "hammer",
	["node_modules"]  = "shippingbox.fill",
	["vendor"]        = "shippingbox",
	["src"]           = "chevron.left.forwardslash.chevron.right",
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

-- ── SwiftUI-style row builder ────────────────────────────────────────────

local function makeIconSquare(name, colorIdx)
	local style = barStyle(colorIdx)
	local iconName = FOLDER_ICONS[name] or "folder.fill"
	local sq = ns.ZStack {
		fixedWidth  = 30,
		fixedHeight = 30,
		cornerRadius = 7,
		background   = style.bg,
	}
	sq:add(ns.SystemImage { name = iconName, size = 14, weight = "medium", color = "white" })
	return sq
end

local function makeGroupedRow(child, colorIdx, ctrl, parentKb)
	local pct = parentKb > 0
		and string.format("%.1f%%", child.kb / parentKb * 100) or ""
	local row = ns.HStack {
		fillWidth     = true,
		fixedHeight   = 48,
		paddingHorizontal = 14,
		spacing       = 12,
		alignment     = "center",
		onDoubleClick = function() ctrl:startScan(child.path) end,
		contextMenu   = makeContextMenuItems(ctrl, child),
	}
	row:add(makeIconSquare(child.name, colorIdx))
	row:add(ns.Text { child.name, size = 13 })
	row:add(ns.Spacer {})
	row:add(ns.Text { Model.humanKb(child.kb), size = 13, color = "secondary" })
	return row
end

local function makeGroupSeparator()
	local sep = ns.HStack { fillWidth = true, fixedHeight = 1 }
	sep:add(ns.VStack { fixedWidth = 56, fixedHeight = 1 })
	sep:add(ns.VStack { flexGrow = 1, fixedHeight = 1, background = "separator" })
	return sep
end

-- ── Suggestions section ──────────────────────────────────────────────────

local function buildSuggestions(tree)
	local items = {}
	for _, child in ipairs(tree.children) do
		local hint = CLEANABLE[child.name]
		if hint then
			items[#items + 1] = { node = child, hint = hint }
		end
	end
	table.sort(items, function(a, b) return a.node.kb > b.node.kb end)
	return items
end

local function makeSuggestionsView(suggestions, ctrl)
	if #suggestions == 0 then return nil end

	local container = ns.VStack {
		fillWidth    = true,
		spacing      = 0,
		alignment    = "leading",
		cornerRadius = 10,
		background   = "controlBackground",
		clipsToBounds = true,
	}

	for i, s in ipairs(suggestions) do
		local row = ns.HStack {
			fillWidth     = true,
			fixedHeight   = 56,
			paddingHorizontal = 14,
			spacing       = 12,
			alignment     = "center",
			onDoubleClick = function() ctrl:startScan(s.node.path) end,
			contextMenu   = makeContextMenuItems(ctrl, s.node),
		}
		local iconName = FOLDER_ICONS[s.node.name] or "archivebox.fill"
		local sq = ns.ZStack {
			fixedWidth  = 30,
			fixedHeight = 30,
			cornerRadius = 7,
			background  = "systemOrange",
		}
		sq:add(ns.SystemImage { name = iconName, size = 14, weight = "medium", color = "white" })
		row:add(sq)

		local info = ns.VStack { spacing = 1, alignment = "leading" }
		info:add(ns.Text { s.node.name .. "  " .. Model.humanKb(s.node.kb),
			size = 13, weight = "medium" })
		info:add(ns.Text { s.hint, size = 11, color = "secondary" })
		row:add(info)

		row:add(ns.Spacer {})
		row:add(ns.Button {
			title = "Reveal",
			style = "plain",
			action = function() ns.revealInFinder(s.node.path) end,
		})
		container:add(row)
		if i < #suggestions then container:add(makeGroupSeparator()) end
	end

	return ns.VStack {
		fillWidth = true,
		spacing   = 6,
		alignment = "leading",
		ns.Text { "Recommendations", size = 12, weight = "bold", color = "secondary" },
		container,
	}
end

-- ── Children list (SwiftUI grouped style) ────────────────────────────────

local function makeChildrenList(tree, ctrl)
	if #tree.children == 0 then return nil end

	local parentKb = math.max(tree.kb, 1)
	local container = ns.VStack {
		fillWidth    = true,
		spacing      = 0,
		alignment    = "leading",
		cornerRadius = 10,
		background   = "controlBackground",
		clipsToBounds = true,
	}

	for i, child in ipairs(tree.children) do
		container:add(makeGroupedRow(child, i - 1, ctrl, parentKb))
		if i < #tree.children then
			container:add(makeGroupSeparator())
		end
	end

	return ns.VStack {
		fillWidth = true,
		spacing   = 6,
		alignment = "leading",
		ns.Text { "Contents", size = 12, weight = "bold", color = "secondary" },
		container,
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

	local childrenView = makeChildrenList(tree, self)
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
