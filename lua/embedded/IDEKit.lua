-- Embedded by IDEKit.dylib; public callers load one native Lua module.
local ns = require("AppKit")
local bridge = require("AppKitNative")

local IDEKit = {}

-- PluginHost is owned by the IDE app. IDEKit only exposes the common editor
-- chrome; keeping discovery in examples/ide prevents the framework from
-- becoming coupled to one application's plugin catalog.

-- ControlBar: thin header strip, like Xcode's DVTControlBar.
-- Props: title (string), height (number, default 28), leading/buttons (view arrays).
function IDEKit.ControlBar(props)
	props = props or {}
	local height = props.height or 28

	-- Edge groups must retain their intrinsic width. HStack normally expands on
	-- its main axis, which would make a trailing button group occupy half the
	-- header and visually center its controls instead of pinning them right.
	local function edgeGroup(controls)
		return ns.HStack {
			spacing = 4,
			flexGrow = 0,
			flexShrink = 0,
			table.unpack(controls),
		}
	end

	-- Row of items: leading | title | Spacer | buttons
	local rowItems = {
		fixedHeight = height,
		paddingHorizontal = 8,
		alignment = "center",
		spacing = 6,
	}
	if props.leading then
		rowItems[#rowItems + 1] = edgeGroup(props.leading)
	end
	if props.title then
		rowItems[#rowItems + 1] = ns.Text {
			props.title,
			size = 11,
			weight = "semibold",
			color = "secondary",
		}
	end
	rowItems[#rowItems + 1] = ns.Spacer()
	local buttons = props.buttons or props.trailing
	if buttons then
		rowItems[#rowItems + 1] = edgeGroup(buttons)
	end

	-- fixedHeight pins the total bar height; flexGrow=0 prevents vertical expansion.
	-- fillWidth=true makes it span the full column width inside HSplit.
	return ns.VStack {
		fixedHeight = height + 1,   -- row + 1px separator
		flexGrow = 0,
		fillWidth = true,
		spacing = 0,
		ns.HStack(rowItems),
		ns.Separator(),
	}
end

-- _areaContent: wrap a content view so it fills remaining vertical space.
local function wrapContent(view)
	if not view then return nil end
	-- Give the content flexGrow=1 so it expands to fill the area under the ControlBar.
	view.flexGrow = 1
	view.fillWidth = true
	return view
end

-- NavigatorArea: left sidebar panel.
-- Props: title, content (view).
-- Mirrors Xcode's IDENavigatorArea / NSView_ControlledBy_IDENavigatorArea.
function IDEKit.NavigatorArea(props)
	props = props or {}
	return ns.VStack {
		spacing = 0,
		IDEKit.ControlBar { title = props.title },
		wrapContent(props.content),
	}
end

-- EditorArea: centre editing panel.
-- Props: title, content (view), leading/buttons ControlBar items.
-- Mirrors Xcode's IDEEditorArea / DVTSplitView_ControlledBy_IDEEditorArea.
function IDEKit.EditorArea(props)
	props = props or {}
	return ns.VStack {
		flexGrow = props.flexGrow or 1,
		spacing = 0,
		IDEKit.ControlBar {
			title = props.title,
			leading = props.leading,
			buttons = props.buttons or props.trailing,
		},
		wrapContent(props.content),
	}
end

-- PreviewArea: canvas / preview panel.
-- Props: title, content (view).
-- Mirrors Xcode's macOS preview: a real content view hosted inline (no chrome).
-- The canvas intercept (ns.Window → ns.VStack) is already equivalent to
-- Xcode's approach of displaying content-only with no NSWindow frame.
function IDEKit.PreviewArea(props)
	props = props or {}
	local toolbarRow = ns.HStack {
		flexGrow = 0,
		flexShrink = 0,
		spacing = 4,
	}
	local area = ns.VStack {
		flexGrow = props.flexGrow or 1,
		spacing = 0,
		IDEKit.ControlBar {
			title = props.title or "Canvas",
			leading = props.leading,
			buttons = { toolbarRow },
		},
		wrapContent(props.content),
	}
	IDEKit._canvasToolbarTarget = toolbarRow
	IDEKit._canvasToolbarParent = area
	return area
end

-- WorkspaceLayout: root 3-panel HSplit.
-- Props: navigator, editor, preview — each a view produced by the area helpers.
-- Mirrors Xcode's workspace root NSSplitView.
function IDEKit.WorkspaceLayout(props)
	props = props or {}
	return ns.HSplit {
		flexGrow = 1,
		proportions = { 1, 2, 2 },
		props.navigator,
		props.editor,
		props.preview,
	}
end

-- SearchView: Xcode-style Open Quickly palette.
-- File discovery, filtering, selection, datasource replacement, and palette
-- state all live in Lua. AppKit supplies only generic native primitives.
local SEARCH_WIDTH = 520
local SEARCH_COLLAPSED_HEIGHT = 48
local SEARCH_EXPANDED_HEIGHT = 360
local SEARCH_FIELD_HEIGHT = 36
local SEARCH_ROW_HEIGHT = 28
local SEARCH_CORNER_RADIUS = 10
local SEARCH_PADDING_HORIZONTAL = 8
local SEARCH_PADDING_VERTICAL = 6

local SearchView = {}
SearchView.__index = SearchView

local function fileName(path)
	return path:match("([^/\\]+)$") or path
end

local function collectFiles(root, maxDepth)
	local result = {}

	local function walk(items)
		if not items then return end
		for _, item in ipairs(items) do
			if item.directory then
				walk(item.children)
			elseif item.path then
				result[#result + 1] = item.path
			end
		end
	end

	walk(ns.readDirectory(root, maxDepth or 5))
	table.sort(result, function(a, b)
		return a:lower() < b:lower()
	end)
	return result
end

function SearchView:_setExpanded(expanded)
	if self._expanded == expanded then return end
	self._expanded = expanded
	self._resultsView.hidden = not expanded
	ns.resizeWindow(
		self._panel,
		SEARCH_WIDTH,
		expanded and SEARCH_EXPANDED_HEIGHT or SEARCH_COLLAPSED_HEIGHT,
		"top")
	ns.relayout(self._content, SEARCH_WIDTH)
end

function SearchView:_replaceResults(query)
	self._query = query or ""
	local lower = self._query:lower()
	local results = {}

	if lower ~= "" then
		for _, path in ipairs(self._files) do
			local name = fileName(path)
			if name:lower():find(lower, 1, true)
				or path:lower():find(lower, 1, true) then
				results[#results + 1] = {
					name = name,
					path = path,
				}
			end
		end
	end

	self._results = results
	self._selectedIndex = #results > 0 and 1 or nil
	self._resultsView:replaceRows(results)
	self:_setExpanded(#results > 0)
	if self._selectedIndex then
		self._resultsView:selectRow(self._selectedIndex - 1)
	end
end

function SearchView:_select(index)
	local count = #self._results
	if count == 0 then return end
	if index < 1 then index = count end
	if index > count then index = 1 end
	self._selectedIndex = index
	self._resultsView:selectRow(index - 1)
end

function SearchView:_activate(row)
	row = row or (self._selectedIndex and self._results[self._selectedIndex])
	if not row or not row.path then return end
	self._onSelect(row.path)
	self:hide()
end

function SearchView:_handleCommand(command)
	if command == "moveDown" then
		self:_select((self._selectedIndex or 0) + 1)
		return true
	elseif command == "moveUp" then
		self:_select((self._selectedIndex or 1) - 1)
		return true
	elseif command == "submit" then
		if self._selectedIndex then
			self._resultsView:activateRow(self._selectedIndex - 1)
		end
		return true
	elseif command == "cancel" then
		self:hide()
		return true
	end
	return false
end

function SearchView:setFiles(files)
	self._files = files or {}
	self._usesExplicitFiles = true
	self:_replaceResults(self._query)
end

function SearchView:setRootDir(root)
	self._rootDir = root or "."
	self._usesExplicitFiles = false
	self._files = {}
	self:_replaceResults("")
end

function SearchView:setQuery(query)
	self._searchField.stringValue = query or ""
	self:_replaceResults(query or "")
end

function SearchView:resultCount()
	return #self._results
end

function SearchView:isExpanded()
	return self._expanded
end

function SearchView:show(window)
	if not self._usesExplicitFiles then
		self._files = collectFiles(self._rootDir, self._maxDepth)
	end
	self._parentWindow = window
	self:setQuery("")
	ns.present(self._panel, window, {
		offsetY = (SEARCH_EXPANDED_HEIGHT - SEARCH_COLLAPSED_HEIGHT) / 2,
	})
	ns.focus(self._panel, self._searchField)
end

function SearchView:hide()
	ns.dismiss(self._panel)
	self._parentWindow = nil
end

function IDEKit.SearchView(props)
	props = props or {}
	local onSelect = props.onSelect or props.action
	if type(onSelect) ~= "function" then
		error("SearchView requires onSelect or action callback")
	end

	local self = setmetatable({
		_onSelect = onSelect,
		_rootDir = props.rootDir or ".",
		_maxDepth = props.maxDepth or 5,
		_files = props.files or {},
		_usesExplicitFiles = props.files ~= nil,
		_results = {},
		_expanded = false,
	}, SearchView)

	self._resultsView = ns.OutlineView {
		header = false,
		bordered = false,
		alternatingRows = false,
		drawsBackground = false,
		style = "plain",
		rowHeight = SEARCH_ROW_HEIGHT,
		indentation = 0,
		flexGrow = 1,
		flexBasis = 0,
		minHeight = 0,
		hidden = true,
		columns = {
			{ id = "name", title = "Name", systemImage = "doc.text" },
		},
		onSelect = function(_, rowIndex)
			self._selectedIndex = rowIndex + 1
		end,
		onActivate = function(_, _, row)
			self:_activate(row)
		end,
	}

	self._searchField = ns.TextField {
		placeholder = props.placeholder or "Open Quickly — type a file name",
		accessibilityLabel = props.accessibilityLabel or "Open Quickly",
		bezeled = false,
		bordered = false,
		drawsBackground = false,
		focusRing = false,
		size = 20,
		fixedHeight = SEARCH_FIELD_HEIGHT,
		fillWidth = true,
		onChange = function(value)
			self:_replaceResults(value)
		end,
		onCommand = function(command)
			return self:_handleCommand(command)
		end,
	}

	self._panel, self._content = ns.Panel {
		width = SEARCH_WIDTH,
		height = SEARCH_COLLAPSED_HEIGHT,
		material = "popover",
		cornerRadius = SEARCH_CORNER_RADIUS,
		paddingHorizontal = SEARCH_PADDING_HORIZONTAL,
		paddingVertical = SEARCH_PADDING_VERTICAL,
		spacing = 0,
		self._searchField,
		self._resultsView,
	}
	return self
end

-- Editor: code-editor view backed by NSTextView.
-- The actual editor behavior lives in Plugins/TextEditor.lua; this wrapper
-- keeps the IDE canvas debounce and preserves the historical IDEKit.Editor API.
function IDEKit.Editor(props)
	props = props or {}
	local canvas = props.canvas
	local eval_version = 0

	local plugin = props.plugin
	if not plugin or type(plugin.create) ~= "function" then
		error("IDEKit.Editor requires props.plugin")
	end
	local editor = plugin.create {
		initialCode = props.initialCode,
		language = props.language or "lua",
	}

	if canvas then
		editor:setChangeHandler(function(text)
			eval_version = eval_version + 1
			local version = eval_version
			bridge._timerAfter(0.3, function()
				if version ~= eval_version then return end
				IDEKit._evalIntoCanvas(canvas, text)
			end)
		end)
	end

	if canvas and props.initialCode then
		IDEKit._evalIntoCanvas(canvas, props.initialCode)
	end

	return editor
end

-- Canvas: the inline preview host view.
-- The canvas itself is a plain VStack that receives the result of _evalIntoCanvas.
-- This matches Xcode's macOS preview architecture: content-only, no window chrome.
function IDEKit.Canvas(props)
	return ns.VStack {
		flexGrow = 1,
	}
end

-- _evalIntoCanvas: evaluate Lua code and render the result into a canvas view.
-- ns.Window is intercepted so scripts that call ns.Window{} render inline.
-- If the script defines a toolbar, buttons are placed in the PreviewArea
-- ControlBar via _setToolbarButtons.
function IDEKit._evalIntoCanvas(canvas, code)
	if not canvas then return end

	local result, err = bridge._eval(code, true)
	bridge._clearContainer(canvas)

	if err then
		local label = bridge._create("NSTextField")
		label.stringValue = err
		label.bezeled = false
		label.drawsBackground = false
		label.editable = false
		label.textColor = bridge._systemColor("secondary")
		bridge._perform(label, "sizeToFit")
		bridge._add(canvas, label)
	elseif result then
		local toolbarItems = bridge._canvas_toolbar_items(result)
		IDEKit._setToolbarButtons(toolbarItems)
		bridge._add(canvas, result)
	end

	bridge._layout(canvas)
end

-- _setToolbarButtons: rebuild toolbar buttons in the CANVAS ControlBar.
-- Items is an array of {icon, tooltip} descriptors from the canvas eval,
-- or nil to clear all buttons.
function IDEKit._setToolbarButtons(items)
	local target = IDEKit._canvasToolbarTarget
	local parent = IDEKit._canvasToolbarParent
	if not target then return end

	bridge._clearContainer(target)
	if items then
		for _, item in ipairs(items) do
			if item.icon then
				local btn = bridge._symbolButton(item.icon, item.tooltip or item.label)
				bridge._add(target, btn)
			end
		end
	end
	if parent then bridge._layout(parent) end
end

function IDEKit.renderCanvas(code, width, height)
	local result, err = bridge._eval(code, true)
	if err then return nil, err end
	local png = bridge._renderToPNG(result, width or 400, height or 300)
	return png, nil
end

return IDEKit
