local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("examples.snippets.Model")

local VIEWS = "examples/snippets/views/"

local ACTIONS = {
	newSnippet = function(self) self:newSnippet() end,
	toggleFavorite = function(self) self:toggleFavorite() end,
	runSnippet = function(self) self:runSnippet() end,
}

local function languageOptions()
	return {
		"lua",
		"javascript",
		"python",
		"json",
		"markdown",
		"shell",
		"swift",
		"text",
	}
end

local function indexOf(array, value)
	for index, item in ipairs(array) do
		if item == value then return index end
	end
	return 1
end

local function buildTagButtons(self)
	local tags = Model.tagRows(self.selectedFolder)
	local children = {}
	for _, tag in ipairs(tags) do
		children[#children + 1] = ns.Button {
			title = tag.name,
			style = "plain",
			action = function()
				self.query = tag.name
				self:refreshSnippets()
			end,
		}
	end
	if #children == 0 then
		children[#children + 1] = ns.Text "No tags in this folder"
	end
	return ns.HStack {
		spacing = 8,
		paddingHorizontal = 4,
		children,
	}
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		selectedFolder = Model.state.selectedFolder or "all",
		selectedSnippetId = Model.state.selectedSnippetId,
		query = "",
		window = nil,
		groupList = nil,
		snippetList = nil,
		tagList = nil,
		searchField = nil,
		editor = nil,
		outputView = nil,
		languagePicker = nil,
	}, Controller)
end

function Controller:refreshGroups()
	if self.groupList then
		self.groupList:replaceRows(Model.folderRows())
	end
	if self.tagList then
		self.tagList:replaceRows(Model.tagRows(self.selectedFolder))
	end
end

function Controller:showSelectedSnippet()
	if not self.editor then return end
	local snippet = Model.findById(self.selectedSnippetId)
	if not snippet then
		self.editor.text = "-- no snippet selected"
		self.editor.language = "text"
		if self.outputView then self.outputView.text = "" end
		return
	end
	self.editor.text = snippet.code or ""
	self.editor.language = snippet.language or "text"
	if self.languagePicker then
		self.languagePicker:selectIndex(indexOf(languageOptions(), self.editor.language) - 1)
	end
	if self.window then
		self.window.title = snippet.title .. " · Snippets"
	end
	Model.recordRecent(snippet.id)
	self:refreshGroups()
	if self.outputView then self.outputView.text = "" end
end

function Controller:refreshSnippets()
	if not self.snippetList then return end
	local rows = {}
	for _, snippet in ipairs(Model.filterSnippets(self.selectedFolder, self.query)) do
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
		if self.outputView then self.outputView.text = "" end
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
		folder = self.selectedFolder == "all" and "productivity" or self.selectedFolder,
		language = "lua",
		favorite = false,
		summary = "A freshly created snippet ready for editing.",
		tags = { "custom" },
		code = "-- New snippet\nprint(\"hello from lua-objc\")\n",
	}
	Model.snippets[#Model.snippets + 1] = snippet
	self.selectedSnippetId = id
	self.selectedFolder = "all"
	self.query = ""
	self:refreshGroups()
	self:refreshSnippets()
end

function Controller:toggleFavorite()
	if not self.selectedSnippetId then return end
	local snippet = Model.findById(self.selectedSnippetId)
	if not snippet then return end
	Model.toggleFavorite(snippet.id)
	self:refreshSnippets()
	self:refreshGroups()
end

function Controller:runSnippet()
	if not self.selectedSnippetId then return end
	local snippet = Model.findById(self.selectedSnippetId)
	if not snippet then return end
	local output, err = Model.executeSnippet(snippet)
	Model.recordRecent(snippet.id)
	if self.outputView then
		self.outputView.text = err and (err .. "\n\n" .. output) or output
		self.outputView.language = snippet.language or "text"
	end
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
			{ id = "name", title = "Folders", width = 146 },
			{ id = "count", title = "Count", width = 42, alignment = "right" },
		},
	}

	self.tagList = ns.List {
		flexGrow = 0,
		fixedHeight = 120,
		style = "plain",
		header = false,
		alternatingRows = false,
		columns = {
			{ id = "name", title = "Tags", width = 180 },
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
			{ id = "favorite", title = "★", width = 32, alignment = "center" },
		},
	}

	self.languagePicker = ns.Picker {
		options = languageOptions(),
		value = 1,
		action = function(index)
			if not self.selectedSnippetId then return end
			local snippet = Model.findById(self.selectedSnippetId)
			if not snippet then return end
			snippet.language = languageOptions()[index] or "text"
			self.editor.language = snippet.language
		end,
	}

	self.editor = ns.TextEditor {
		language = "lua",
		wrapMode = false,
		flexGrow = 1,
	}

	self.outputView = ns.TextEditor {
		language = "text",
		editable = false,
		selectable = true,
		drawsBackground = false,
		fixedHeight = 120,
		text = "Run a snippet to preview output.",
	}

	cfg.sidebar = ns.VStack {
		flexGrow = 1,
		padding = 10,
		spacing = 8,
		self.searchField,
		self.groupList,
		self.tagList,
		self.snippetList,
	}

	cfg.content = ns.VStack {
		flexGrow = 1,
		padding = 10,
		spacing = 10,
		ns.HStack {
			spacing = 8,
			alignment = "left",
			self.languagePicker,
			ns.Text "Snippet detail",
		},
		self.editor,
		self.outputView,
	}

	self.window = ns.Window(cfg)
	self.groupList:onRowSelect(function(_, _, row)
		if row and row._id then
			self.selectedFolder = row._id
			self.selectedSnippetId = nil
			self.query = ""
			self.searchField.value = ""
			self:refreshGroups()
			self:refreshSnippets()
		end
	end)
	self.tagList:onRowSelect(function(_, _, row)
		if row and row._id then
			self.query = row._id
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
