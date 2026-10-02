local Model = require("data.model")
local Filesystem = require("apps.diskmap.helpers.Filesystem")
local Guide = require("apps.diskmap.helpers.Guide")
local Help = require("apps.diskmap.helpers.Help")

-- The Learn pages: the Storage Guide and Diskmap Help, and macOS Folders.
local routes = {}

-- The books the topics route reads, by the `source` their page names in
-- app.xml: the template that draws one topic, the header's second line,
-- "No <noun> mentions …" when a search finds nothing, the chapters a search
-- leaves and what a topic's button does (nil for no button).
local SOURCES = {
	Guide = {topic = "topics/GuideTopic", noun = "guide topic",
		summary = "Where macOS keeps things, why they grow and what is safe to do about them. Sizes are measured on this Mac.",
		present = function(_, query) return Guide.presentation(query) end,
		follow = function(self, topic) return topic.open and function() self.app.open(topic.open) end end},
	Help = {topic = "topics/HelpTopic", noun = "help topic",
		summary = "How to find what uses your storage and free up space safely. To search help from anywhere, use the Help menu.",
		present = function(self, query) return Help.presentation(query, self.app.shortcuts(), self.app.links) end,
		follow = function(self, topic)
			local target = topic.target
			return topic.link and function()
				if self.app.pages[target] then self.app.show(target) else self.app.command(target) end
			end
		end},
}

-- A page of chapters of topics to read, one route for both books.
routes.topics = {view = "pages/Topics"}

function routes.topics:before() self.book = SOURCES[self.params.source] end

-- The answer is asked again only when the search changes or a scan starts or
-- ends: scan progress would otherwise rebuild every topic and collapse the
-- one being read, and the sizes it measures are shown once it is done.
function routes.topics:data(state)
	local book, query = self.book, state.query or ""
	local key = query .. tostring(Model.db.scan.running == true)
	if not self.answer or self.key ~= key then self.key, self.answer = key, book.present(self, state.query) end
	local handlers = {}
	for _, chapter in ipairs(self.answer.chapters) do
		for _, topic in ipairs(chapter.topics) do handlers["open_" .. topic.id] = book.follow(self, topic) end
	end
	return {chapters = self.answer.chapters, empty = self.answer.empty, summary = book.summary, topic = book.topic,
		noun = book.noun, query = query, expandAll = query ~= "", handlers = handlers}
end

function routes.topics:deactivate() self.answer = nil end

-- The macOS Folders page. Sizes of the locations no scan resource covers are
-- measured once per scan: Inventory clears `folderSizes` when a new scan
-- begins, so a draw after the scan that finds them gone measures again.
-- Until then (and while the scan runs) the rows say "Not measured"; the
-- page's own measurement is the page-level `computing` spinner.
routes.filesystem = {view = "pages/Filesystem"}
local filesystem = routes.filesystem

function filesystem:waiting()
	return not (Model.db.folderSizes or Model.db.scan.running) and self.app.service.measure ~= nil
end

function filesystem:rendered()
	local storage, service = Model.db, self.app.service
	if self.measuring or not self:waiting() then return end
	local paths = Filesystem.pending()
	self.measuring = true
	service.measure(paths, function(sizes, states)
		self.measuring = false
		local found = {}
		for index, path in ipairs(paths) do
			found[path] = {bytes = sizes[index] or 0, state = states and states[index] or "measured"}
		end
		storage.folderSizes = found
		self.app.refresh()
	end)
end

-- Each row's Finder and Diskmap buttons are named by their location.
function filesystem:data(state)
	local storage = Model.db
	local data = Filesystem.presentation(storage.folderSizes, state.fullDiskAccess, state.query)
	data.query = state.query or ""
	if self:waiting() then data.computing = "Measuring folders…" end
	data.handlers = {}
	for _, area in ipairs(data.areas) do
		for index, row in ipairs(area.rows) do
			local key = area.id .. "_" .. index
			data.handlers["reveal_" .. key] = function() self.app.service.reveal(row.path) end
			if row.resource then data.handlers["open_" .. key] = function() self.app.open(row.resource) end end
		end
	end
	return data
end

return routes
