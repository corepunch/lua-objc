local commands = require("ui.commands")
local Help = require("apps.diskmap.models.Help")
local Guide = require("apps.diskmap.models.Guide")
local Navigation = require("apps.diskmap.controllers.NavigationController")
local Controller = {}; Controller.__index = Controller

-- The menu bar: its actions, their validation and the Help menu's search
-- topics. Window.etlua lays the menus out; this controller supplies what
-- they do. `handlers` come from the root controller:
-- `show(id)`, `destination()`, `scanning()`, `refresh()`, `cancel()`,
-- `settings()`, `find()`, `search(page, text)`, `emptyTrash()`, `review()`,
-- `history()`, `openFolder()`, `quickLook()`/`canQuickLook()` for the
-- current page's selection, and `navigation`, the sidebar's back/forward
-- history.
function Controller.new(model, service, handlers)
	return setmetatable({model = model, service = service, handlers = handlers}, Controller)
end

-- Buttons on help topics that run a command rather than open a page.
Controller.commandLinks = {
	refresh = "Refresh",
	privacy = "Full Disk Access Settings…",
	find = "Search",
	emptyTrash = "Empty Trash…",
}

local TRASH = "user-trash"

function Controller:canEmptyTrash()
	local row = self.model.resources:find(TRASH)
	return row ~= nil and (row:validateEmpty()) == true
end

-- Actions and validators named by Window.etlua's <Commands>.
function Controller:actions()
	local h = self.handlers
	local actions = {
		settings = h.settings,
		refresh = h.refresh,
		canRefresh = function() return not h.scanning() end,
		cancel = h.cancel,
		canCancel = function() return h.scanning() end,
		emptyTrash = h.emptyTrash,
		canEmptyTrash = function() return self:canEmptyTrash() end,
		storageSettings = function() self.service.openSettings() end,
		privacy = function() self.service.openSettings("privacy") end,
		diskUtility = function() self.service.openDiskUtility() end,
		find = h.find,
		help = function() h.show("help") end,
		shortcuts = function() h.search("help", "Keyboard shortcuts") end,
		guide = function() h.show("guide") end,
		filesystem = function() h.show("filesystem") end,
		tour = h.tour,
		back = function() h.navigation:back() end,
		canGoBack = function() return h.navigation:canGoBack() end,
		forward = function() h.navigation:forward() end,
		canGoForward = function() return h.navigation:canGoForward() end,
		review = h.review,
		history = h.history,
		openFolder = h.openFolder,
		quickLook = h.quickLook,
		canQuickLook = function() return h.canQuickLook() end,
		openScan = h.openScan,
		compareScan = h.compareScan,
		canCompareScan = function() return not h.scanning() end,
		exportScan = h.exportScan,
		canExportScan = function() return not h.scanning() end,
	}
	for _, page in ipairs(Navigation.destinations) do
		if page.id then
			actions["page_" .. page.id] = function() h.show(page.id) end
			-- A page of work this Mac does not do is not in the sidebar.
			actions["isPage_" .. page.id] = function() return h.navigation:index(page.id) ~= nil, h.destination() == page.id end
		end
	end
	for _, topic in ipairs(Help.searchTopics()) do
		actions["helpTopic_" .. topic.id] = function() h.search("help", topic.title) end
	end
	for _, chapter in ipairs(Guide.chapters) do
		for _, topic in ipairs(chapter.topics) do
			actions["guideTopic_" .. topic.id] = function() h.search("guide", topic.title) end
		end
	end
	return actions
end

-- Template data for the menus: sidebar pages grouped by section for the Go
-- menu, and every help and guide topic for the Help menu's search field.
function Controller:data()
	local sections, current = {}, nil
	for _, page in ipairs(Navigation.destinations) do
		-- The pages that lead the sidebar without a header form a group too.
		if page.section or not current then
			current = {title = page.title, pages = {}}
			table.insert(sections, current)
		end
		if not page.section then table.insert(current.pages, page) end
	end
	local topics = {}
	for _, topic in ipairs(Help.searchTopics()) do
		table.insert(topics, {title = topic.title, keywords = topic.keywords, action = "helpTopic_" .. topic.id})
	end
	for _, chapter in ipairs(Guide.chapters) do
		for _, topic in ipairs(chapter.topics) do
			table.insert(topics, {title = topic.title, action = "guideTopic_" .. topic.id,
				keywords = table.concat({"storage guide", chapter.title, topic.summary}, " ")})
		end
	end
	return {sections = sections, helpTopics = topics}
end

-- Every keyboard shortcut in the installed menu bar as `{title, key,
-- modifiers}`, titled "Menu › Item", for the Keyboard shortcuts help topic.
function Controller:shortcuts(spec)
	local built = commands.build(spec)
	local list = {}
	local function walk(items, path)
		for _, item in ipairs(items) do
			if item.items then walk(item.items, path .. " › " .. item.title)
			elseif not item.separator and (item.keyEquivalent or "") ~= "" then
				table.insert(list, {title = path .. " › " .. item.title, key = item.keyEquivalent, modifiers = item.modifiers})
			end
		end
	end
	for _, menu in ipairs(built.menus) do walk(menu.items, menu.title) end
	return list
end

-- Button titles for help topics: pages open by name, commands by title.
function Controller.links()
	local links = {}
	for _, page in ipairs(Navigation.destinations) do
		if page.id then links[page.id] = "Show " .. page.name end
	end
	for id, title in pairs(Controller.commandLinks) do links[id] = title end
	return links
end

return Controller
