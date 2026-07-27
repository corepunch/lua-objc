local ns = require("AppKit")
local bridge = require("bridge")

local FIND = {
	rowHeight = 28,
}

local FindInFiles = {}
FindInFiles.__index = FindInFiles

local function fileName(path)
	return path:match("([^/\\]+)$") or path
end

local function collectProjectFiles(rootDir)
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
	walk(ns.readDirectory(rootDir, 5))
	return result
end

local function searchFiles(files, query)
	local results = {}
	local lower = query:lower()
	for _, path in ipairs(files) do
		local name = fileName(path)
		if name:lower():find(lower, 1, true)
			or path:lower():find(lower, 1, true) then
			results[#results + 1] = {
				name = name,
				path = path,
			}
		end
	end
	table.sort(results, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return results
end

function FindInFiles:setQuery(query)
	self._query = query or ""
	local results = searchFiles(self._files, self._query)
	self._resultsView:replaceRows(results)
end

local function create(props)
	props = props or {}
	local onSelect = props.onSelect

	local self = setmetatable({
		_query = "",
		_files = props.files or {},
		_rootDir = props.rootDir,
	}, FindInFiles)

	if self._rootDir and not props.files then
		self._files = collectProjectFiles(self._rootDir)
	end

	self._searchField = ns.TextField {
		placeholder = props.placeholder or "Find in Files...",
		accessibilityLabel = props.accessibilityLabel or "Find in Files",
		bezeled = false,
		bordered = false,
		drawsBackground = false,
		focusRing = false,
		size = 13,
		fillWidth = true,
		fillHeight = false,
		flexGrow = 1,
		flexBasis = 0,
		minWidth = 0,
		onChange = function(value)
			self:setQuery(value)
		end,
	}

	self._searchIcon = ns.SystemImage {
		"magnifyingglass",
		accessibilityLabel = "Search",
		size = 14,
		weight = "regular",
		color = "secondary",
		fixedWidth = 22,
		fixedHeight = 22,
		flexGrow = 0,
		flexShrink = 0,
	}

	self._searchHeader = ns.HStack {
		fixedHeight = 32,
		fillWidth = true,
		alignment = "center",
		paddingHorizontal = 8,
		spacing = 6,
		self._searchIcon,
		self._searchField,
	}

	self._resultsView = ns.OutlineView {
		header = false,
		bordered = false,
		alternatingRows = false,
		drawsBackground = false,
		style = "plain",
		rowHeight = FIND.rowHeight,
		indentation = 0,
		flexGrow = 1,
		flexBasis = 0,
		minHeight = 0,
		columns = {
			{ id = "name", title = "Name", systemImage = "doc.text" },
		},
		onSelect = function(_, rowIndex, rowData)
			if rowData and rowData.path and onSelect then
				onSelect(rowData.path)
			end
		end,
	}

	local root = ns.VStack {
		flexGrow = 1,
		spacing = 0,
		self._searchHeader,
		ns.Separator(),
		self._resultsView,
	}

	self._root = root
	return self, root
end

return create
