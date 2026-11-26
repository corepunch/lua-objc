local xml = require("ui.xml")

-- The app's words: resources.xml in English, and for each other language a
-- resources.<id>.xml whose strings replace the English ones (ui/resources.lua).
-- Read once per language; a template is rendered with the table of the
-- language the app speaks at that moment (`data.resources`), so changing the
-- language changes the next render.
local Words = {}

local PATH = "apps/adventure-arena/resources.xml"
local loaded = {}

function Words.load(language)
	if not loaded[language] then loaded[language] = xml.loadResources(PATH, language) end
	return loaded[language]
end

return Words
