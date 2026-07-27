-- SearchView: Xcode-style Open Quickly palette.
-- File discovery, filtering, selection, datasource replacement, and palette
-- state all live in Lua. AppKit supplies only generic native primitives.
local ns = require("AppKit")
local bridge = require("bridge")

local SEARCH_WIDTH = 520
local SEARCH_COLLAPSED_HEIGHT = 48
local SEARCH_EXPANDED_HEIGHT = 360
local SEARCH_HEADER_HEIGHT = 48
local SEARCH_FIELD_HEIGHT = 28
local SEARCH_ICON_SIZE = 22
local SEARCH_ICON_FRAME = 28
local SEARCH_ROW_HEIGHT = 28
local SEARCH_CORNER_RADIUS = 16
local SEARCH_HEADER_PADDING_HORIZONTAL = 14
local SEARCH_HEADER_SPACING = 8
local SEARCH_SHADOW_RADIUS = 22
local SEARCH_SHADOW_OPACITY = 0.28
local SEARCH_SHADOW_OFFSET_Y = 8
local SEARCH_SHADOW_INSET = 30

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

local function create(props)
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
		placeholder = props.placeholder or "Open Quickly",
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

	self._searchIcon = ns.SystemImage {
		"magnifyingglass",
		accessibilityLabel = "Search",
		size = SEARCH_ICON_SIZE,
		weight = "regular",
		color = "secondary",
		fixedWidth = SEARCH_ICON_FRAME,
		fixedHeight = SEARCH_ICON_FRAME,
		flexGrow = 0,
		flexShrink = 0,
	}

	self._searchHeader = ns.HStack {
		fixedHeight = SEARCH_HEADER_HEIGHT,
		fillWidth = true,
		alignment = "center",
		paddingHorizontal = SEARCH_HEADER_PADDING_HORIZONTAL,
		spacing = SEARCH_HEADER_SPACING,
		self._searchIcon,
		self._searchField,
	}

	self._panel, self._content = ns.Panel {
		width = SEARCH_WIDTH,
		height = SEARCH_COLLAPSED_HEIGHT,
		material = "popover",
		cornerRadius = SEARCH_CORNER_RADIUS,
		shadowRadius = SEARCH_SHADOW_RADIUS,
		shadowOpacity = SEARCH_SHADOW_OPACITY,
		shadowOffsetY = SEARCH_SHADOW_OFFSET_Y,
		shadowInset = SEARCH_SHADOW_INSET,
		padding = 0,
		spacing = 0,
		self._searchHeader,
		self._resultsView,
	}
	return self
end

return create
