local Model = require("data.model")
local Session = require("apps.adventure-arena.models.Session")

-- Autosaves, one per adventure: the command history and random seed that
-- replay the story, plus what the library shows about it (room and score)
-- without starting an engine. The store's `saves` table, keyed by gameId;
-- every change is written at once through the store's `documents.saves`
-- (a JSON document in the app's folder), so the model never touches files.
-- `save:adventure()` is the adventure it belongs to (models/Adventures.lua).
local SavedGames, SavedGame = Model:extend("saves", {primaryKey = "gameId", relations = {
	{"adventure", belongsTo = "adventures", key = "gameId"},
}})

-- The time a save is stamped with; tests replace it.
SavedGames.clock = os.time

local function validRecord(record)
	return type(record) == "table" and type(record.gameId) == "string"
		and type(record.commands) == "table"
end

-- The saves in a document's table, skipping anything that is not one.
function SavedGames.restore(loaded)
	local records = {}
	if type(loaded) == "table" and type(loaded.games) == "table" then
		for _, record in ipairs(loaded.games) do
			if validRecord(record) then table.insert(records, record) end
		end
	end
	return records
end

function SavedGames:persist()
	local documents = Model.db.documents
	local document = documents and documents.saves
	if not (document and document.save) then return end
	local games = {}
	for _, record in ipairs(self:list()) do table.insert(games, record) end
	document.save({ games = games })
end

-- A story with no commands yet is not worth resuming: opening a book is not
-- reading it. Saving it would put every browsed title on the shelf.
function SavedGames:record(snapshot)
	if not validRecord(snapshot) then return false end
	if #snapshot.commands == 0 then return false end
	local record = {}
	for key, value in pairs(snapshot) do record[key] = value end
	record.updated = SavedGames.clock()
	local existing = self:find(snapshot.gameId)
	if existing then existing:delete() end
	self:create(record)
	self:persist()
	return true
end

function SavedGames:remove(gameId)
	local record = self:find(gameId)
	if not record then return false end
	record:delete()
	self:persist()
	return true
end

-- Most recently played first; ties keep a stable order by id.
function SavedGames:list()
	return self:select(nil, { order = function(a, b)
		if (a.updated or 0) ~= (b.updated or 0) then return (a.updated or 0) > (b.updated or 0) end
		return a.gameId < b.gameId
	end })
end

function SavedGames:latest()
	return self:list()[1]
end

-- Where a saved story stands, in the words a reader uses: the room, then
-- the status line and how far the score has come. Nil when its adventure
-- has left the catalog.
function SavedGame:progress()
	local game = self:adventure()
	if not game then return nil end
	local score, maxScore = tonumber(self.score) or 0, tonumber(self.maxScore) or 0
	return {
		game = game,
		place = self.room or game.title,
		status = Session.statusLine(game, score, maxScore, tonumber(self.moves) or 0),
		progress = maxScore > 0 and math.max(0, math.min(1, score / maxScore)) or 0,
	}
end

-- Every story in progress, newest first.
function SavedGames:inProgress()
	local entries = {}
	for _, record in ipairs(self:list()) do
		local entry = record:progress()
		if entry then table.insert(entries, entry) end
	end
	return entries
end

return SavedGames
