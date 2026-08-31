local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("examples.snippets.Model")

local VIEWS = "examples/snippets/views/"

local ACTIONS = {
	newSnippet = function(self) self:newSnippet() end,
	toggleFavorite = function(self) self:toggleFavorite() end,
}

local function categoryRows()
	local counts = Model.groupCounts()
	local rows = {}
	for _, group in ipairs(Model.groups) do
		rows[#rows + 1] = {
			_id = group.id,
			name = group.name,
			count = tostring(counts[group.id] or 0),
			icon = group.icon,
		}
	end
	return rows
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		selectedGroup = "all",
		selectedSnippetId = nil,
		query = "",
		window = nil,
		groupList = nil,
		snippetList = nil,
		searchField = nil,
		editor = nil,
	}, Controller)
end

function Controller:refreshGroups()
	if self.groupList then
		self.groupList:replaceRows(categoryRows())
	end
end

function Controller:showSelectedSnippet()
	if not self.editor then return end
	local snippet = Model.findById(self.selectedSnippetId)
	if not snippet then
		self.editor.text = "-- no snippet selected"
		self.editor.language = "text"
		return
	end
	self.editor.text = snippet.code or ""
	self.editor.language = snippet.language or "text"
	if self.window then
		self.window.title = snippet.title .. " · Snippets"
	end
end

function Controller:refreshSnippets()
	if not self.snippetList then return end
	local rows = {}
	for _, snippet in ipairs(Model.filteredSnippets(self.selectedGroup, self.query)) do
		rows[#rows + 1] = {
			_id = snippet.id,
			name = snippet.title,
			language = snippet.language,
			summary = snippet.summary,
			favorite = snippet.favorite and "★" or "",
		}
	end
	self.snippetList:replaceRows(rows)
	if #rows == 0 then
		self.selectedSnippetId = nil
		self.editor.text = "-- no snippets match your search"
		self.editor.language = "text"
		return
	end
	local selectedStillVisible = false
	for _, row in ipairs(rows) do
		if row._id == self.selectedSnippetId then
			selectedStillVisible = true
			break
		end
	end
	if not selectedStillVisible then
		self.selectedSnippetId = rows[1]._id
	end
	self:showSelectedSnippet()
end

function Controller:newSnippet()
	local id = "custom-" .. tostring(os.time())
	local snippet = {
		id = id,
		title = "Untitled snippet",
		group = self.selectedGroup == "all" and "productivity" or self.selectedGroup,
		language = "lua",
		favorite = false,
		summary = "A freshly created snippet ready for editing.",
		tags = { "custom" },
		code = "-- New snippet\nprint(\"hello from lua-objc\")\n",
	}
	Model.snippets[#Model.snippets + 1] = snippet
	self.selectedSnippetId = id
	self.selectedGroup = "all"
	self:refreshGroups()
	self:refreshSnippets()
end

function Controller:toggleFavorite()
	if not self.selectedSnippetId then return end
	local snippet = Model.findById(self.selectedSnippetId)
	if not snippet then return end
	snippet.favorite = not snippet.favorite
	self:refreshSnippets()
end

function Controller:createWindow()
	local cfg = xml.renderFile(VIEWS .. "Window.etlua")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	self.searchField = ns.SearchField {
		placeholder = "Search snippets",
		accessibilityLabel = "Search snippets",
		controlSize = "regular",
		fixedHeight = 32,
		fillWidth = true,
		onChange = function(value)
			self.query = value or ""
			self:refreshSnippets()
		end,
	}

	self.groupList = ns.List {
		flexGrow = 1,
		style = "sourceList",
		header = false,
		alternatingRows = false,
		columns = {
			{ id = "name", title = "Groups", width = 146 },
			{ id = "count", title = "Count", width = 44, alignment = "right" },
		},
	}

	self.snippetList = ns.List {
		flexGrow = 1,
		style = "plain",
		header = false,
		alternatingRows = false,
		rowHeight = 54,
		columns = {
			{ id = "name", title = "Snippet", width = 220, cell = { secondary = "summary" } },
			{ id = "language", title = "Lang", width = 82 },
			{ id = "favorite", title = "★", width = 30, alignment = "center" },
		},
	}

	self.editor = ns.TextEditor {
		language = "lua",
		wrapMode = false,
		flexGrow = 1,
	}

	cfg.sidebar = ns.VStack {
		flexGrow = 1,
		padding = 10,
		spacing = 8,
		self.searchField,
		self.groupList,
		self.snippetList,
	}

	cfg.content = ns.VStack {
		flexGrow = 1,
		padding = 10,
		spacing = 10,
		ns.Text("Snippet detail"),
		self.editor,
	}

	self.window = ns.Window(cfg)
	self.groupList:onRowSelect(function(_, _, row)
		if row and row._id then
			self.selectedGroup = row._id
			self:refreshSnippets()
		end
	end)
	self.snippetList:onRowSelect(function(_, _, row)
		if row and row._id then
			self.selectedSnippetId = row._id
			self:showSelectedSnippet()
		end
	end)
	self:refreshGroups()
	self:refreshSnippets()
	return self.window
end

return Controller
