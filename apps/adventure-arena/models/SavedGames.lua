local SavedGames = {}
SavedGames.__index = SavedGames

-- Autosaves, one per adventure: the command history and random seed that
-- replay the story, plus what the library shows about it (chapter, room and
-- score) without starting an engine. The store is injected, so the model
-- never touches files; `store.load()` returns the saved table and
-- `store.save(table)` persists it.
local VERSION = 1

local function validRecord(record)
	return type(record) == "table" and type(record.gameId) == "string"
		and type(record.commands) == "table"
end

function SavedGames.new(options)
	options = options or {}
	local self = setmetatable({
		store = options.store,
		clock = options.clock or os.time,
		records = {},
	}, SavedGames)
	local loaded = self.store and self.store.load and self.store.load()
	if type(loaded) == "table" and loaded.version == VERSION and type(loaded.games) == "table" then
		for _, record in ipairs(loaded.games) do
			if validRecord(record) then self.records[record.gameId] = record end
		end
	end
	return self
end

function SavedGames:persist()
	if not (self.store and self.store.save) then return end
	local games = {}
	for _, record in ipairs(self:list()) do table.insert(games, record) end
	self.store.save({ version = VERSION, games = games })
end

function SavedGames:find(gameId)
	return self.records[gameId]
end

-- A story with no commands yet is not worth resuming: opening a book is not
-- reading it. Saving it would put every browsed title on the shelf.
function SavedGames:record(snapshot)
	if not validRecord(snapshot) then return false end
	if #snapshot.commands == 0 then return false end
	local record = {}
	for key, value in pairs(snapshot) do record[key] = value end
	record.updated = self.clock()
	self.records[snapshot.gameId] = record
	self:persist()
	return true
end

function SavedGames:remove(gameId)
	if not self.records[gameId] then return false end
	self.records[gameId] = nil
	self:persist()
	return true
end

-- Most recently played first; ties keep a stable order by id.
function SavedGames:list()
	local list = {}
	for _, record in pairs(self.records) do table.insert(list, record) end
	table.sort(list, function(a, b)
		if (a.updated or 0) ~= (b.updated or 0) then return (a.updated or 0) > (b.updated or 0) end
		return a.gameId < b.gameId
	end)
	return list
end

function SavedGames:latest()
	return self:list()[1]
end

return SavedGames
