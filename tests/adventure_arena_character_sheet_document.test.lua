local t = require("TestKit")
local CharacterSheet = require("apps.adventure-arena.services.CharacterSheet")

local function contains(s, part)
	return s:find(part, 1, true) ~= nil
end

local dossier = {
	language = "ru", title = "Огни Меридиана", profile = "Искра", name = [[Алёна <Гром> & "Свет"]],
	rows = {
		{ label = "Ловкость", value = 30, group = "abilities", rankLabel = "Особый <ранг>" },
		{ label = "Интуиция", value = 20, group = "abilities" },
		{ label = "Мощь & скорость", value = 40, group = "powers" },
		{ label = "Здоровье", value = 85, maximum = 90, group = "resources" },
		{ label = "Карма", value = 50, group = "resources" },
	},
}
local document = CharacterSheet.document(dossier)
t.expect(contains(document, '<html lang="ru">'))
t.expect(contains(document, "Алёна &lt;Гром&gt; &amp; &quot;Свет&quot;"), "hero name is escaped")
t.expect(contains(document, "Мощь &amp; скорость"), "attribute labels are escaped")
t.expect(contains(document, "Особый &lt;ранг&gt;"), "rank labels are escaped")
t.expect(contains(document, 'id="abilities"') and contains(document, 'id="powers"') and contains(document, 'id="resources"'))
t.expect(contains(document, "85 / 90"), "current and maximum remain distinct")
t.expect(contains(document, "<dd>50</dd>"), "a resource without a maximum shows only the tracked number")
t.expect(contains(document, "Эти поля не заполняются из игры.") and contains(document, "Таланты и снаряжение"))
t.expect(contains(document, "size: auto") and contains(document, "@media print"), "uses the selected printer paper")
t.expect(not contains(document, "<Гром>"))
t.expect(not contains(document, "http://") and not contains(document, "https://"), "HTML works offline")

local generic = CharacterSheet.document({
	language = "de", title = "Die Höhle", profile = "Wanderer", name = "Frieda",
	rows = {{ label = "Ausdauer", value = 6, group = "custom" }, { label = "Focus", value = 3 }},
})
t.expect(contains(generic, '<html lang="de">') and contains(generic, "Charakterbogen"))
t.expect(contains(generic, 'id="stats"') and contains(generic, "Ausdauer") and contains(generic, "Focus"))
t.expect(not contains(generic, 'id="abilities"') and not contains(generic, 'id="powers"'))
t.expect(not contains(generic, "Talente &amp; Ausrüstung"), "generic systems get general notes only")
t.expect(not contains(generic, 'scope="col">Rang'), "omit the rank column if no row exposes a rank")

local templatePath, shared
t.expect(CharacterSheet.share({
	_readFile = function(path)
		templatePath = path
		local file = assert(io.open(path, "rb"))
		local body = file:read("a")
		file:close()
		return body
	end,
	shareFiles = function(files)
		shared = files[1]
		return true
	end,
}, dossier), "template works with the native virtual file reader")
t.expect(contains(templatePath, "/views/exports/CharacterSheet.etlua"))
t.assertEqual(shared.name, "character-sheet.html")
t.assertEqual(shared.text, document)

os.exit(t.summary() and 0 or 1)
