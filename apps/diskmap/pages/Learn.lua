local Categories = require("apps.diskmap.models.Categories")
local Locations = require("apps.diskmap.models.Locations")
local Model = require("data.model")
local Filesystem = require("apps.diskmap.helpers.Filesystem")
local Guide = require("apps.diskmap.helpers.Guide")
local Help = require("apps.diskmap.helpers.Help")

-- The Learn pages: the Storage Guide and Diskmap Help, and macOS Folders.
local routes = {}

-- The books the topics route reads, by the `source` their page names in
-- app.xml: the template that draws one topic, the header's second line, its
-- chapters and what a topic's button does (nil for no button).
local SOURCES = {
	Guide = {topic = "topics/GuideTopic", anchor = "topic_",
		summary = "Where macOS keeps things, why they grow and what is safe to do about them. Sizes are measured on this Mac.",
		present = function() return Guide.presentation(Categories.measured, Locations.advice) end,
		follow = function(self, topic) return topic.open and function() self.app.open(topic.open) end end},
	Help = {topic = "topics/HelpTopic", anchor = "help_",
		summary = "How to find what uses your storage and free up space safely. To search help from anywhere, use the Help menu.",
		present = function(self) return Help.presentation(self.app.shortcuts(), self.app.links) end,
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

-- Search and the Help menu open the page on one topic: its disclosure open,
-- scrolled to the top of the page once it is drawn.
function routes.topics:focus(params) self.opened, self.reveal, self.answer = params.topic, params.topic, nil end
function routes.topics:location() return {topic = self.opened} end

function routes.topics:rendered(refs)
	if not self.reveal then return end
	refs.page:scrollTo(self.book.anchor .. self.reveal, false, "top")
	self.reveal = nil
end

-- The answer is asked again only when a scan starts or ends: scan progress
-- would otherwise rebuild every topic and collapse the one being read, and
-- the sizes it measures are shown once it is done.
function routes.topics:data()
	local book = self.book
	local key = tostring(Model.db.scan.running == true)
	if not self.answer or self.key ~= key then self.key, self.answer = key, book.present(self) end
	local handlers = {}
	for _, chapter in ipairs(self.answer.chapters) do
		for _, topic in ipairs(chapter.topics) do handlers["open_" .. topic.id] = book.follow(self, topic) end
	end
	return {chapters = self.answer.chapters, subtitle = book.summary, topic = book.topic, opened = self.opened, handlers = handlers}
end

function routes.topics:deactivate() self.answer, self.opened, self.reveal = nil, nil, nil end

-- The macOS Folders page. Sizes of the locations no scan resource covers are
-- measured once per scan: Inventory clears `folderSizes` when a new scan
-- begins, so a draw after the scan that finds them gone measures again.
-- Until then (and while the scan runs) the rows say "Not measured"; the
-- page's own measurement is the page-level `computing` spinner.
routes.filesystem = {view = "pages/Filesystem"}
local filesystem = routes.filesystem

function filesystem:waiting()
	return not (Model.db.folderSizes or Model.db.scan.running)
end

function filesystem:rendered()
	local storage, service = Model.db, self.app.service
	if self.measuring == storage.scan or not self:waiting() then return end
	local paths = Filesystem.pending(Categories:facts())
	local generation = storage.scan
	self.measuring = generation
	service.measure(paths, function(sizes, states)
		if self.app.closed or storage.scan ~= generation or self.measuring ~= generation then return end
		self.measuring = nil
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
	local data = Filesystem.presentation(storage.folderSizes, state.fullDiskAccess, Categories:facts())
	if self:waiting() then data.computing = "Measuring folders…" end
	data.subtitle = "Where macOS keeps things, what each folder is for and how much it takes"
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
