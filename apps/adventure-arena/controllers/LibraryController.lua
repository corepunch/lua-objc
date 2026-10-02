local Adventures = require("apps.adventure-arena.models.Adventures")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local Session = require("apps.adventure-arena.models.Session")

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	return setmetatable({
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		focus = options.focus or function() end,
		selectTab = options.selectTab or function() return false end,
		openSession = assert(options.openSession, "session callback is required"),
		onSavesChanged = options.onSavesChanged or function() end,
		query = "",
	}, Controller)
end

-- Where a saved story stands, in the words a reader uses: the room, then
-- the status line and how far the score has come.
function Controller:progressEntry(record)
	local game = record:adventure()
	if not game then return nil end
	local place = record.room or game.title
	local maxScore = tonumber(record.maxScore) or 0
	return {
		game = game,
		place = place,
		status = Session.statusLine(game, tonumber(record.score) or 0, maxScore, tonumber(record.moves) or 0),
		progress = maxScore > 0 and math.max(0, math.min(1, (tonumber(record.score) or 0) / maxScore)) or 0,
	}
end

function Controller:inProgress()
	local entries = {}
	for _, record in ipairs(SavedGames:list()) do
		local entry = self:progressEntry(record)
		if entry then table.insert(entries, entry) end
	end
	return entries
end

-- `origin` names the navigation stack a tap came from ("library", "search",
-- "bookshelf"), so pages open in the tab the reader is using.
function Controller:presentation()
	local games, featured = Adventures:all(), Adventures:featured()
	local shelves, topRated, genres = Adventures:shelves(), Adventures:topRated(), Adventures:genres()
	local actions = {
		search = function(text) self:search(text) end,
		openCreate = function() self.selectTab("create") end,
	}
	for index, game in ipairs(featured) do
		actions["featured_" .. index] = function() self:showGame(game.id, "library") end
	end
	for _, game in ipairs(games) do
		actions[game.id] = function() self:showGame(game.id, "library") end
	end
	for index, shelf in ipairs(shelves) do
		actions["shelf_" .. index] = function() self:showCollection(shelf.title, "library") end
	end
	for index, entry in ipairs(topRated) do
		actions["chart_" .. index] = function() self:showGame(entry.game.id, "library") end
	end
	for index, genre in ipairs(genres) do
		actions["genre_" .. index] = function() self:showCollection(genre.title, "library") end
	end
	return {
		games = games, featured = featured, shelves = shelves, topRated = topRated, genres = genres,
		actions = actions,
	}
end

-- The Discover page's "Continue Reading" row.
function Controller:continueShelf()
	local entries = self:inProgress()
	local actions = {}
	for index, entry in ipairs(entries) do
		actions["continue_" .. index] = function()
			self.focus("library")
			self.openSession(entry.game.id)
		end
	end
	return { continueGames = entries, actions = actions }
end

-- The Library tab: every story in progress with Start Over and Remove.
function Controller:bookshelf()
	local entries = self:inProgress()
	local actions = {
		browseDiscover = function() self.selectTab("library") end,
	}
	for index, entry in ipairs(entries) do
		local id = entry.game.id
		actions["continue_" .. index] = function()
			self.focus("bookshelf")
			self.openSession(id)
		end
		actions["restart_" .. index] = function()
			self.focus("bookshelf")
			self.openSession(id, true)
		end
		actions["remove_" .. index] = function() self:removeSaved(id) end
	end
	return { entries = entries, actions = actions }
end

function Controller:removeSaved(id)
	if not SavedGames:remove(id) then return false end
	self.onSavesChanged()
	return true
end

function Controller:showGame(id, origin)
	local game = Adventures:find(id)
	if not game then return false end
	self.focus(origin)
	local related = Adventures:related(id)
	local record = SavedGames:find(id)
	local saved = record and self:progressEntry(record) or nil
	local actions = {
		play = function() self.openSession(id) end,
		restart = function() self.openSession(id, true) end,
		back = self.back,
	}
	for index, other in ipairs(related) do
		actions["related_" .. index] = function() self:showGame(other.id, origin) end
	end
	self.push("pages/Detail", { game = game, related = related, saved = saved, actions = actions })
	return true
end

function Controller:showCollection(title, origin)
	local games = Adventures:collection(title)
	if #games == 0 then return false end
	self.focus(origin)
	local actions = {}
	for _, game in ipairs(games) do
		actions[game.id] = function() self:showGame(game.id, origin) end
	end
	self.push("pages/Collection", { title = title, games = games, actions = actions })
	return true
end

-- Search results are a retained template: each keystroke re-describes the
-- result list and the template swaps only when the description changes.
function Controller:attachSearch(template)
	self.searchResults = template
	return self:search(self.query)
end

function Controller:search(query)
	self.query = tostring(query or ""):match("^%s*(.-)%s*$")
	if not self.searchResults then return nil end
	local results, genres = Adventures:search(self.query), Adventures:genres()
	local actions = {}
	for index, game in ipairs(results) do
		actions["result_" .. index] = function() self:showGame(game.id, "search") end
	end
	for index, genre in ipairs(genres) do
		actions["genre_" .. index] = function() self:showCollection(genre.title, "search") end
	end
	local _, refs = self.searchResults:update({
		query = self.query, results = results, genres = genres, actions = actions,
	})
	return results, refs
end

return Controller
