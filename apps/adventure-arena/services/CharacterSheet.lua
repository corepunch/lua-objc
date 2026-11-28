local etlua = require("etlua")
local CharacterSheet = {}

local TEMPLATE = "apps/adventure-arena/views/exports/CharacterSheet.etlua"

local words = {
	en = {
		sheet = "Character sheet", adventure = "Adventure", profile = "Profile",
		abilities = "Core abilities", powers = "Powers", resources = "Current status", stats = "Statistics",
		attribute = "Attribute", rank = "Rank", value = "Value", print = "Print sheet",
		notes = "Field notes", handwritten = "For handwritten notes. Not read from the game.",
		powerNotes = "Power uses & limits", talents = "Talents & gear", contacts = "Contacts", history = "History",
	},
	de = {
		sheet = "Charakterbogen", adventure = "Abenteuer", profile = "Profil",
		abilities = "Grundfähigkeiten", powers = "Kräfte", resources = "Aktueller Status", stats = "Werte",
		attribute = "Attribut", rank = "Rang", value = "Wert", print = "Bogen drucken",
		notes = "Einsatznotizen", handwritten = "Für handschriftliche Notizen. Keine Daten aus dem Spiel.",
		powerNotes = "Kräfte & Grenzen", talents = "Talente & Ausrüstung", contacts = "Kontakte", history = "Vorgeschichte",
	},
	ru = {
		sheet = "Лист персонажа", adventure = "Приключение", profile = "Профиль",
		abilities = "Основные характеристики", powers = "Сверхспособности", resources = "Текущее состояние", stats = "Параметры",
		attribute = "Характеристика", rank = "Ранг", value = "Число", print = "Распечатать лист",
		notes = "Полевые заметки", handwritten = "Для записей от руки. Эти поля не заполняются из игры.",
		powerNotes = "Силы и ограничения", talents = "Таланты и снаряжение", contacts = "Связи", history = "История",
	},
}

local function loadTemplate(readFile)
	if readFile then
		return assert(readFile(TEMPLATE))
	end
	local file = assert(io.open(TEMPLATE, "rb"))
	local source = assert(file:read("a"))
	file:close()
	return source
end

function CharacterSheet.document(sheet, readFile)
	local language = words[sheet.language] and sheet.language or "en"
	local text = words[language]
	local groups = { abilities = {}, powers = {}, resources = {}, stats = {} }
	for _, row in ipairs(sheet.rows) do
		local group = groups[row.group] or groups.stats
		local value = row.maximum and tostring(row.value) .. " / " .. tostring(row.maximum) or tostring(row.value)
		group[#group + 1] = { label = row.label, rank = row.rankLabel, value = value }
	end
	local tables = {}
	for _, key in ipairs({ "abilities", "powers", "stats" }) do
		local rows, hasRanks = groups[key], false
		for _, row in ipairs(rows) do
			if type(row.rank) == "string" and row.rank ~= "" then hasRanks = true end
		end
		if #rows > 0 then
			tables[#tables + 1] = { id = key, title = text[key], rows = rows, hasRanks = hasRanks }
		end
	end

	local notes = { text.notes }
	if #groups.abilities > 0 and #groups.powers > 0 then
		notes = { text.powerNotes, text.talents, text.contacts, text.history }
	end
	return assert(etlua.render(loadTemplate(readFile), {
		language = language, text = text, sheet = sheet, resources = groups.resources, tables = tables, notes = notes,
	}))
end

function CharacterSheet.share(ns, sheet)
	local document = CharacterSheet.document(sheet, ns._readFile)
	if ns.shareFiles then
		return ns.shareFiles({ { name = "character-sheet.html", text = document } }, "CharacterSheet")
	end
	local temporary = os.tmpname()
	os.remove(temporary)
	local path = temporary .. ".html"
	local file, err = io.open(path, "wb")
	if not file then return false, err end
	local written, writeError = file:write(document)
	local closed, closeError = file:close()
	if not written or not closed then
		os.remove(path)
		return false, writeError or closeError
	end
	return ns.openPath(path)
end

return CharacterSheet
