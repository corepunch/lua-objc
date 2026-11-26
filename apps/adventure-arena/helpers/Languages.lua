-- The languages Adventure Arena speaks: one catalog (catalog/<id>.lua) and
-- one set of words (resources.<id>.xml; English is resources.xml) for each.
-- Pure: the device's preference and the reader's choice come in as arguments.
local Languages = {}

-- `speechLocale` is the dictation locale; `title` is the language written in
-- itself, as pickers name languages.
local LIST = {
	{ id = "en", title = "English", speechLocale = "en-US" },
	{ id = "de", title = "Deutsch", speechLocale = "de-DE" },
}
local DEFAULT = "en"

function Languages.list() return LIST end
function Languages.default() return DEFAULT end

function Languages.find(id)
	for _, language in ipairs(LIST) do
		if language.id == id then return language end
	end
end

-- The index of a language in the list (1-based), or nil.
function Languages.index(id)
	for index, language in ipairs(LIST) do
		if language.id == id then return index end
	end
end

function Languages.speechLocale(id)
	return (Languages.find(id) or Languages.find(DEFAULT)).speechLocale
end

-- The first of the device's preferred language tags ("de-AT", "en_GB") whose
-- language `has` a catalog; English when none does.
function Languages.preferred(tags, has)
	for _, tag in ipairs(tags or {}) do
		local id = tostring(tag):match("^(%a+)"):lower()
		if Languages.find(id) and has[id] then return id end
	end
	return DEFAULT
end

-- Lower case that knows the accents of Latin-1 (Ä, Ö, Ü), which string.lower
-- leaves alone: search must find "Öffnen" typed as "öffnen".
function Languages.lower(text)
	if not utf8.len(text) then return text:lower() end
	local lowered = {}
	for _, code in utf8.codes(text) do
		if (code >= 0xC0 and code <= 0xDE and code ~= 0xD7) then code = code + 32
		elseif code < 128 then code = string.lower(string.char(code)):byte() end
		table.insert(lowered, utf8.char(code))
	end
	return table.concat(lowered)
end

return Languages
