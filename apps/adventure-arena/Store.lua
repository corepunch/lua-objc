local Model = require("data.model")
local Adventures = require("apps.adventure-arena.models.Adventures")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SavedGames = require("apps.adventure-arena.models.SavedGames")

-- Adventure Arena's store: the tables its models read (lua/data/model.lua).
--
--   adventures   the catalog, in editorial order (models/Adventures.lua)
--   saves        one autosave per adventure (models/SavedGames.lua)
--   reading      the reader's settings, one row (models/ReadingSettings.lua)
--   documents    where saves and settings are written: {saves, reading},
--                each {load(), save(value)}; none in headless tests
local Store = {}

-- A new store, bound as the one every model reads. `options.games`
-- replaces the bundled catalog; `options.documents` are the JSON documents
-- saves and settings load from and are written to.
function Store.new(options)
	options = options or {}
	local documents = options.documents or {}
	local function load(document) return document and document.load and document.load() end
	local games = {}
	for _, game in ipairs(options.games or require("apps.adventure-arena.catalog.Adventures")) do
		table.insert(games, Adventures.prepare(game))
	end
	return Model.bind({
		adventures = games,
		saves = SavedGames.restore(load(documents.saves)),
		reading = {ReadingSettings.restore(load(documents.reading))},
		documents = documents,
	})
end

return Store
