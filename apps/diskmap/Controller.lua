local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("apps.diskmap.Model")

local VIEWS = "apps/diskmap/views/"

local function renderTemplate(templateFile, context)
	return xml.renderFile(VIEWS .. templateFile, context)
end

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

local function makeIcicle(node, availW, ctrl)
	if availW < MIN_BAR_W or #node.children == 0 then return nil end

	local nodeKb = math.max(node.kb, 1)
	local row = ns.HStack {
		fixedWidth = availW,
		spacing    = SIBLING_GAP,
		alignment  = "top",
	}

	local budget = availW
	local count  = 0
	for _, child in ipairs(node.children) do
		if budget <= 0 then break end
		local w = math.floor(child.kb / nodeKb * availW)
		if w < MIN_BAR_W then break end
		w = math.min(w, budget)

		local style = barStyle(count)
		local sizeStr = Model.humanKb(child.kb)
		local labelText = child.name .. "  " .. sizeStr

		local bar = ns.HStack {
			fixedWidth    = w,
			fixedHeight   = BAR_H,
			cornerRadius  = 3,
			background    = style.bg,
			alignment     = "center",
			clipsToBounds = true,
			onClick       = function() ctrl:selectNode(child) end,
			onDoubleClick = function() ctrl:startScan(child.path) end,
			contextMenu   = makeContextMenuItems(ctrl, child),
			hoverTooltip  = { title = child.name, detail = sizeStr },
		}
		if w >= MIN_LABEL_W then
			bar:add(ns.Text {
				labelText,
				size       = 11,
				weight     = "semibold",
				color      = style.fg,
				fixedWidth = w - 8,
				alignment  = "center",
				lineLimit  = 1,
			})
		end

		if count > 0 then
			row:add(ns.VStack { fixedWidth = SIBLING_GAP, fixedHeight = BAR_H })
		end
		row:add(bar)
		budget = budget - w - SIBLING_GAP
		count  = count + 1
	end

	if budget > MIN_BAR_W and count > 0 then
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

	return row
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

-- ── Header with folder info (etlua template) ─────────────────────────

local function makeHeaderBar(tree, diskInfo)
	local parts = {}
	parts[#parts + 1] = Model.humanKb(tree.kb)
	if diskInfo and diskInfo.freeKb then
		parts[#parts + 1] = "Free: " .. Model.humanKb(diskInfo.freeKb)
	end
	parts[#parts + 1] = tostring(#tree.children) .. " items"

	local context = {
		folderName = tree.name or "Folder",
		headerStats = table.concat(parts, "   ·   "),
	}

	return renderTemplate("HeaderBar.etlua", context)
end

-- ── Status bar (etlua template) ───────────────────────────────────────

local function makeStatusBar(tree, diskInfo)
	local parts = {}
	parts[#parts + 1] = "Total: " .. Model.humanKb(tree.kb)
	parts[#parts + 1] = tostring(#tree.children) .. " items"
	if diskInfo and diskInfo.freeKb then
		parts[#parts + 1] = "Free: " .. Model.humanKb(diskInfo.freeKb)
	end

	local context = {
		statusText = table.concat(parts, "   ·   "),
	}

	return renderTemplate("StatusBar.etlua", context)
end

-- ── Right sidebar with folder details ────────────────────────────────────

local LAYOUT = {
	sidebarWidth = 228,
	rightWidth = 330,
	contentPadding = 24,
	rowHeight = 49,
	panelRadius = 12,
}

local USAGE_COLORS = {
	"systemBlue", "systemPurple", "systemOrange", "systemYellow", "systemGray",
}

local NAV_ITEMS = {
	{ title = "Disk Map", icon = "chart.pie.fill" },
	{ title = "Suggestions", icon = "lightbulb" },
	{ title = "Large Files", icon = "doc.fill" },
	{ title = "Applications", icon = "app.fill" },
	{ title = "File Types", icon = "doc.on.doc.fill" },
}

local function makeRightSidebar(tree, diskInfo)
	local folderName = tree.name or "Folder"
	local folderPath = tree.path or "/"
	local itemCount = #tree.children
	local sizeStr = Model.humanKb(tree.kb)

	local panel = ns.VStack {
		fixedWidth = 280,
		flexGrow = 1,
		spacing = 16,
		padding = 16,
		alignment = "top",
		fillHeight = true,
	}

	-- Folder name and size
	panel:add(ns.VStack {
		fillWidth = true,
		spacing = 6,
		alignment = "leading",
		ns.Text { folderName, size = 16, weight = "bold" },
		ns.Text { folderPath, size = 11, color = "secondary", lineLimit = 2 },
	})

	-- Info section
	panel:add(ns.VStack {
		fillWidth = true,
		spacing = 8,
		alignment = "leading",
		cornerRadius = 8,
		background = "controlBackground",
		padding = 12,
		ns.HStack {
			fillWidth = true,
			ns.Text { "Size", size = 11, color = "secondary" },
			ns.Spacer {},
			ns.Text { sizeStr, size = 12, weight = "medium" },
		},
		ns.HStack {
			fillWidth = true,
			ns.Text { "Items", size = 11, color = "secondary" },
			ns.Spacer {},
			ns.Text { tostring(itemCount), size = 12, weight = "medium" },
		},
	})

	if diskInfo and diskInfo.freeKb then
		panel:add(ns.VStack {
			fillWidth = true,
			spacing = 8,
			alignment = "leading",
			cornerRadius = 8,
			background = "controlBackground",
			padding = 12,
			ns.Text { "Disk Usage", size = 11, weight = "semibold" },
			ns.HStack {
				fillWidth = true,
				ns.Text { "Free", size = 11, color = "secondary" },
				ns.Spacer {},
				ns.Text { Model.humanKb(diskInfo.freeKb), size = 12 },
			},
		})
	end

	-- Quick Actions
	panel:add(ns.VStack {
		fillWidth = true,
		spacing = 6,
		alignment = "leading",
		ns.Text { "Quick Actions", size = 11, weight = "semibold", color = "secondary" },
		ns.Button {
			title = "Open in Terminal",
			style = "plain",
			fillWidth = true,
			action = function()
				os.execute(string.format("open -a Terminal %q", folderPath))
			end,
		},
		ns.Button {
			title = "Copy Path",
			style = "plain",
			fillWidth = true,
			action = function()
				ns.copyToClipboard(folderPath)
			end,
		},
	})

	panel:add(ns.Spacer {})

	return panel
end

local function makeNavSidebar()
	local sidebar = ns.VStack {
		fixedWidth = LAYOUT.sidebarWidth,
		fillWidth = true,
		spacing = 8,
		padding = 16,
		alignment = "leading",
	}
	for i, item in ipairs(NAV_ITEMS) do
		local row = ns.HStack {
			fillWidth = true,
			fixedHeight = 42,
			paddingHorizontal = 14,
			spacing = 14,
			alignment = "center",
			cornerRadius = 9,
			background = i == 1 and "selectedControlColor" or nil,
		}
		row:add(ns.SystemImage { name = item.icon, size = 19, color = i == 1 and "accent" or "label" })
		row:add(ns.Text { item.title, size = 15, color = i == 1 and "accent" or "label" })
		sidebar:add(row)
	end
	sidebar:add(ns.Spacer {})
	local settings = ns.HStack {
		fillWidth = true,
		fixedHeight = 38,
		paddingHorizontal = 14,
		spacing = 14,
		alignment = "center",
	}
	settings:add(ns.SystemImage { name = "gearshape", size = 18, color = "secondary" })
	settings:add(ns.Text { "Settings", size = 14, color = "secondary" })
	sidebar:add(settings)
	return sidebar
end

local function makeBreadcrumb(path)
	local crumbs = {}
	for part in path:gmatch("[^/]+") do crumbs[#crumbs + 1] = part end
	local row = ns.HStack { spacing = 8, alignment = "center" }
	for i, part in ipairs(crumbs) do
		if i > 1 then
			row:add(ns.SystemImage { name = "chevron.right", size = 10, color = "tertiary" })
		end
		row:add(ns.Text { part, size = 14, color = i == #crumbs and "accent" or "secondary", weight = i == #crumbs and "semibold" or "regular" })
	end
	return row
end

local function makeUsageBar(tree)
	local bar = ns.HStack {
		fillWidth = true,
		fixedHeight = 28,
		spacing = 2,
		cornerRadius = 4,
		clipsToBounds = true,
	}
	local total = math.max(tree.kb, 1)
	for i, child in ipairs(tree.children) do
		local width = math.max(4, math.floor((child.kb / total) * 600))
		bar:add(ns.HStack {
			fixedWidth = width,
			fixedHeight = 28,
			background = USAGE_COLORS[((i - 1) % #USAGE_COLORS) + 1],
		})
		if i >= 5 then break end
	end
	bar:add(ns.HStack { flexGrow = 1, fixedHeight = 28, background = "systemGray" })
	return bar
end

local function makeUsageLegend(tree)
	local legend = ns.HStack { fillWidth = true, fixedHeight = 42, spacing = 22, alignment = "top" }
	local total = math.max(tree.kb, 1)
	for i, child in ipairs(tree.children) do
		if i > 5 then break end
		local color = USAGE_COLORS[((i - 1) % #USAGE_COLORS) + 1]
		local item = ns.VStack { spacing = 3, alignment = "leading" }
		item:add(ns.HStack {
			spacing = 7,
			ns.ZStack { fixedWidth = 12, fixedHeight = 12, cornerRadius = 6, background = color },
			ns.Text { child.name, size = 12, weight = "medium" },
		})
		item:add(ns.Text { Model.humanKb(child.kb), size = 11, color = "secondary" })
		legend:add(item)
	end
	return legend
end

local function makeDiskTable(tree, ctrl)
	local tableView = ns.VStack {
		fillWidth = true,
		spacing = 0,
		alignment = "leading",
		cornerRadius = LAYOUT.panelRadius,
		background = "controlBackground",
		clipsToBounds = true,
	}
	local heading = ns.HStack {
		fillWidth = true,
		fixedHeight = 36,
		paddingHorizontal = 12,
		alignment = "center",
	}
	heading:add(ns.Text { "Name", size = 12, color = "secondary" })
	heading:add(ns.Spacer {})
	heading:add(ns.Text { "Size", size = 12, color = "secondary", fixedWidth = 82, alignment = "trailing" })
	heading:add(ns.Text { "Items", size = 12, color = "secondary", fixedWidth = 78, alignment = "trailing" })
	heading:add(ns.Text { "%", size = 12, color = "secondary", fixedWidth = 58, alignment = "trailing" })
	tableView:add(heading)
	local total = math.max(tree.kb, 1)
	for i, child in ipairs(tree.children) do
		local pct = child.kb / total * 100
		local row = ns.HStack {
			fillWidth = true,
			fixedHeight = LAYOUT.rowHeight,
			paddingHorizontal = 12,
			spacing = 10,
			alignment = "center",
			onClick = function() ctrl:selectNode(child) end,
			onDoubleClick = function() ctrl:startScan(child.path) end,
			contextMenu = makeContextMenuItems(ctrl, child),
		}
		row:add(ns.SystemImage { name = "folder.fill", size = 22, color = "systemBlue" })
		row:add(ns.Text { child.name, size = 14, lineLimit = 1, truncation = "tail", flexGrow = 1 })
		row:add(ns.Text { Model.humanKb(child.kb), size = 13, fixedWidth = 82, alignment = "trailing" })
		row:add(ns.Text { tostring(#child.children), size = 13, color = "secondary", fixedWidth = 78, alignment = "trailing" })
		row:add(ns.Text { pct >= 1 and string.format("%.0f%%", pct) or "<1%", size = 13, color = "secondary", fixedWidth = 40, alignment = "trailing" })
		row:add(ns.SystemImage { name = "chevron.right", size = 12, color = "secondary" })
		tableView:add(row)
		if i < #tree.children then tableView:add(ns.Separator {}) end
	end
	return tableView
end

local function makeFolderCard(tree, diskInfo)
	local panel = ns.VStack {
		fillWidth = true,
		spacing = 14,
		padding = 18,
		alignment = "leading",
		cornerRadius = LAYOUT.panelRadius,
		background = "controlBackground",
	}
	local title = ns.HStack { fillWidth = true, spacing = 14, alignment = "center" }
	title:add(ns.SystemImage { name = "folder.fill", size = 42, color = "systemBlue" })
	title:add(ns.VStack { spacing = 2, alignment = "leading", ns.Text { tree.name, size = 17, weight = "bold" }, ns.Text { Model.humanKb(tree.kb), size = 23, weight = "bold" }, ns.Text { tostring(Model.countItems(tree)) .. " items", size = 12, color = "secondary" } })
	panel:add(title)
	panel:add(ns.Separator {})
	panel:add(ns.Text { tree.path, size = 12, color = "secondary", lineLimit = 1, truncation = "middle" })
	local meta = ns.VStack { spacing = 6, alignment = "leading" }
	meta:add(ns.HStack { fillWidth = true, ns.Text { "Kind", size = 12, color = "secondary" }, ns.Spacer {}, ns.Text { "Folder", size = 12 } })
	meta:add(ns.HStack { fillWidth = true, ns.Text { "Contents", size = 12, color = "secondary" }, ns.Spacer {}, ns.Text { tostring(#tree.children) .. " folders", size = 12 } })
	if diskInfo and diskInfo.freeKb then
		meta:add(ns.HStack { fillWidth = true, ns.Text { "Free on disk", size = 12, color = "secondary" }, ns.Spacer {}, ns.Text { Model.humanKb(diskInfo.freeKb), size = 12 } })
	end
	panel:add(meta)
	panel:add(ns.Button { title = "Reveal in Finder", systemImage = "folder", style = "plain", fillWidth = true, action = function() ns.revealInFinder(tree.path) end })
	return panel
end

local function makeSuggestionCard(tree, ctrl)
	local suggestions = buildSuggestions(tree)
	if #suggestions == 0 then return nil end
	local panel = ns.VStack { fillWidth = true, spacing = 0, alignment = "leading", cornerRadius = LAYOUT.panelRadius, background = "controlBackground", clipsToBounds = true }
	panel:add(ns.Text { "Suggestions for this folder", size = 15, weight = "bold", padding = 16 })
	for i, suggestion in ipairs(suggestions) do
		local row = ns.HStack { fillWidth = true, fixedHeight = 56, paddingHorizontal = 14, spacing = 10, alignment = "center" }
		row:add(ns.SystemImage { name = FOLDER_ICONS[suggestion.node.name] or "folder.fill", size = 22, color = "systemBlue" })
		row:add(ns.VStack { spacing = 2, alignment = "leading", flexGrow = 1, ns.Text { suggestion.node.name .. "  " .. Model.humanKb(suggestion.node.kb), size = 12, weight = "medium" }, ns.Text { suggestion.hint, size = 11, color = "secondary", lineLimit = 1 } })
		row:add(ns.Button { title = "Review", style = "plain", action = function() ctrl:startScan(suggestion.node.path) end })
		panel:add(row)
		if i < #suggestions then panel:add(ns.Separator {}) end
		if i >= 3 then break end
	end
	return panel
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
	local main = ns.VStack {
		flexGrow = 1,
		fillWidth = true,
		fillHeight = true,
		spacing = 0,
		alignment = "leading",
	}
	local header = ns.HStack {
		fillWidth = true,
		fixedHeight = 88,
		paddingHorizontal = 26,
		spacing = 16,
		alignment = "center",
		background = "windowBackground",
	}
	header:add(ns.SystemImage { name = "internaldrive.fill", size = 40, color = "secondary" })
	header:add(ns.VStack { spacing = 2, alignment = "leading", ns.Text { "Macintosh HD", size = 22, weight = "bold" }, ns.Text { Model.humanKb(tree.kb) .. " total   ·   " .. (diskInfo and Model.humanKb(diskInfo.usedKb or tree.kb) or Model.humanKb(tree.kb)) .. " used   ·   " .. (diskInfo and Model.humanKb(diskInfo.freeKb or 0) or "—") .. " free", size = 13, color = "secondary" } })
	header:add(ns.Spacer {})
	header:add(ns.SearchField { placeholder = "Search folders…", fixedWidth = 320, fixedHeight = 36, accessibilityLabel = "Search folders" })
	main:add(header)

	local body = ns.HStack { flexGrow = 1, fillWidth = true, fillHeight = true, spacing = 0, alignment = "top" }
	local center = ns.VStack { flexGrow = 1, fillWidth = true, fillHeight = true, spacing = 0, alignment = "leading" }
	local content = ns.VStack { fillWidth = true, spacing = 16, padding = LAYOUT.contentPadding, alignment = "leading" }
	local nav = ns.HStack { fillWidth = true, fixedHeight = 40, spacing = 10, alignment = "center" }
	nav:add(ns.Button { title = "‹", style = "plain", fixedWidth = 34, action = function() self:goBack() end })
	nav:add(ns.Button { title = "›", style = "plain", fixedWidth = 34, action = function() self:goForward() end })
	nav:add(makeBreadcrumb(tree.path))
	content:add(nav)
	local usage = ns.VStack { fillWidth = true, fixedHeight = 86, spacing = 10, alignment = "leading" }
	usage:add(makeUsageBar(tree))
	usage:add(makeUsageLegend(tree))
	content:add(usage)
	local tableContent = ns.VStack { fillWidth = true, spacing = 16, padding = LAYOUT.contentPadding, alignment = "leading" }
	tableContent:add(makeDiskTable(tree, self))
	center:add(ns.VStack { fillWidth = true, fixedHeight = 136, spacing = 0, paddingHorizontal = LAYOUT.contentPadding, alignment = "leading", nav, usage })
	center:add(ns.ScrollView { content = tableContent, vertical = true, flexGrow = 1, fillWidth = true })
	body:add(center)
	local right = ns.VStack { fixedWidth = LAYOUT.rightWidth, fillHeight = true, spacing = 16, padding = 16, alignment = "leading" }
	right:add(makeFolderCard(tree, diskInfo))
	local suggestionCard = makeSuggestionCard(tree, self)
	if suggestionCard then right:add(suggestionCard) end
	right:add(ns.VStack { fillWidth = true, spacing = 8, padding = 14, alignment = "leading", cornerRadius = LAYOUT.panelRadius, background = "controlBackground", ns.Text { "Quick Actions", size = 15, weight = "bold" }, ns.HStack { fillWidth = true, spacing = 8, ns.Button { title = "Open in Terminal", style = "plain", flexGrow = 1, action = function() os.execute(string.format("open -a Terminal %q", tree.path)) end }, ns.Button { title = "Copy Path", style = "plain", flexGrow = 1, action = function() ns.copyToClipboard(tree.path) end } } })
	right:add(ns.Spacer {})
	body:add(right)
	main:add(body)
	main:add(ns.HStack { fillWidth = true, fixedHeight = 30, paddingHorizontal = 24, alignment = "center", background = "windowBackground", ns.Text { tostring(#tree.children) .. " items   " .. Model.humanKb(tree.kb), size = 11, color = "secondary" }, ns.Spacer {}, ns.Text { "Scan completed", size = 11, color = "secondary" }, ns.SystemImage { name = "arrow.clockwise", size = 13, color = "secondary" } })
	local layout = main

	self:showContent(layout)
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

	-- Sidebar: main navigation (Settings-style)
	local sidebar = makeNavSidebar()

	-- Content area
	self.contentArea = ns.VStack { flexGrow = 1, fillWidth = true }

	local rootPath = (arg and arg[1]) or os.getenv("HOME") or "/"

	local cfg = xml.renderFile(VIEWS .. "Window.etlua")
	local sidebarW = LAYOUT.sidebarWidth
	local rightSidebarW = LAYOUT.rightWidth
	self.chartWidth = (cfg.width or 1024) - sidebarW - rightSidebarW - 64
	local workspace = ns.HStack {
		flexGrow = 1,
		fillWidth = true,
		fillHeight = true,
		spacing = 0,
		alignment = "top",
	}
	workspace:add(sidebar)
	workspace:add(self.contentArea)
	cfg.sidebar      = nil
	cfg.sidebarWidth = nil
	cfg.content      = workspace
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
