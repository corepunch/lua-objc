local Model = require("data.model")
local Languages = require("apps.adventure-arena.helpers.Languages")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SavedGames = require("apps.adventure-arena.models.SavedGames")

-- Adventure Arena's store: the tables its models read (lua/data/model.lua).
--
--   adventures   every language's catalog, in editorial order; the models
--                show the ones in the app's language (models/Adventures.lua)
--   deviceLanguage  the first of the device's preferred languages that has a
--                catalog, else English; `forcedLanguage` (a launch argument)
--                and the reader's setting override it (ReadingSettings.language)
--   saves        one autosave per adventure (models/SavedGames.lua)
--   reading      the reader's settings, one row (models/ReadingSettings.lua)
--   documents    where saves and settings are written: {saves, reading},
--                each {load(), save(value)}; none in headless tests
local Store = {}

-- A new store, bound as the one every model reads. `options.games`
-- replaces the bundled catalogs; `options.preferredLanguages` are the device's
-- language tags, `options.language` forces one for this run; `options.documents`
-- are the JSON documents saves and settings load from and are written to.
function Store.new(options)
	options = options or {}
	local documents = options.documents or {}
	local function load(document) return document and document.load and document.load() end
	local games = {}
	if options.games then
		for _, game in ipairs(options.games) do table.insert(games, game) end
	else
		for _, language in ipairs(Languages.list()) do
			for _, entry in ipairs(require("apps.adventure-arena.catalog." .. language.id)) do
				local game = { language = language.id }
				for key, value in pairs(entry) do game[key] = value end
				table.insert(games, game)
			end
		end
	end
	local has = {}
	for _, game in ipairs(games) do
		if game.language then has[game.language] = true end
	end
	if options.language then assert(Languages.find(options.language), "Unknown language " .. tostring(options.language)) end
	return Model.bind({
		adventures = games,
		deviceLanguage = Languages.preferred(options.preferredLanguages, has),
		forcedLanguage = options.language,
		saves = SavedGames.restore(load(documents.saves)),
		reading = {ReadingSettings.restore(load(documents.reading))},
		documents = documents,
	})
end

return Store
