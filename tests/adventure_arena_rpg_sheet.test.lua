_G.__headless = true

local t = require("TestKit")
local Controller = require("apps.adventure-arena.Controller")
local Adventures = require("apps.adventure-arena.models.Adventures")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local CharacterSheet = require("apps.adventure-arena.services.CharacterSheet")

local id = "books.ru.blackout-at-meridian"
local saves
local app = Controller.new {
	preferredLanguages = { "ru-RU", "en-US" },
	documents = { saves = { load = function() return saves end, save = function(value) saves = value end } },
}
app:home()
t.assertEqual(Adventures:find(id).title, "Огни Меридиана")
t.assertEqual(Adventures:search("МЕРИДИАНА")[1].id, id)
t.expect(Adventures:find("books.en.blackout-at-meridian") == nil, "editions have separate catalogs")

local controller = app.sessionController
controller.reduceMotion = function() return true end
controller.model.newSeed = function() return 97 end
t.expect(controller:show(id, true), "Russian edition opens in the normal reader")
local reader = controller.model
t.assertEqual(reader.entries[1].kind, "banner", "the Russian release line is parsed as a banner")
t.expect(not reader.engine:canExportSheet(), "there is no sheet before hero selection")
t.expect(not controller.refs.exportSheet, "the pre-game composer has no print action")
t.assertEqual(reader:linkActions("ИСКРУ")[1].command, "осмотреть искру")
t.assertEqual(reader:suggestions("ОСМОТРЕТЬ ИС")[1].text, "осмотреть искру ")
controller:submitCommand("осмотреть искру")
controller:submitCommand("назвать карточку героя")
controller:submitCommand("Алёна <Гром> & дочь")
t.assertEqual(reader.moves, 0, "setup does not advance the adventure clock")
controller:submitCommand("выбрать искру")
t.assertEqual(reader.moves, 0, "the mission begins at turn zero")
t.expect(reader.engine:canExportSheet(), "selecting a profile enables the character sheet")
t.expect(controller.refs.exportSheet ~= nil, "the print action appears in the normal reader")
controller:submitCommand("север")
t.expect(reader:start(Adventures:find(id), SavedGames:find(id)), "Russian progress replays from an autosave")
t.assertEqual(reader.roomTitle, "Мост Меридиана")
controller:submitCommand("спасти трамвай")
local before = reader:snapshot()
local sheet = reader.engine:characterSheet()
t.assertEqual(sheet.name, "Алёна <Гром> & дочь")
t.assertEqual(sheet.profile, "Искра")
t.assertEqual(#sheet.rows, 10)
for i = 1, 7 do
	t.assertEqual(sheet.rows[i].group, "abilities")
	t.expect(type(sheet.rows[i].rankLabel) == "string" and sheet.rows[i].rankLabel ~= "", "ability rank uses localized text")
end
t.assertEqual(sheet.rows[8].group, "powers")
t.assertEqual(sheet.rows[9].group, "resources")
t.assertEqual(sheet.rows[10].group, "resources")
t.assertEqual(sheet.rows[9].rankLabel, nil, "health is a resource, not an ability rank")
t.assertEqual(sheet.rows[9].label, "Здоровье")
t.assertEqual(sheet.rows[9].value, 85, "export reads live health after a failed rescue")
t.assertEqual(sheet.rows[9].maximum, 90)
t.assertEqual(sheet.rows[10].label, "Карма")
t.assertEqual(sheet.rows[10].value, 50)
local document = CharacterSheet.document(sheet)
t.expect(document:find('<html lang="ru">', 1, true), "the HTML declares the language")
t.expect(document:find("Алёна &lt;Гром&gt; &amp; дочь", 1, true), "player HTML is escaped")
t.expect(document:find("85 / 90", 1, true), "resources include their maximum")
t.expect(type(sheet.rows[8].rankLabel) == "string" and document:find(sheet.rows[8].rankLabel, 1, true), "the PDF-ready HTML includes the actual power rank")
t.expect(document:find("Таланты и снаряжение", 1, true), "the sheet includes a handwritten section")
t.expect(document:find("@media print", 1, true), "the HTML has a print layout")
t.assertEqual(reader:snapshot().moves, before.moves, "export does not take a turn")
t.assertEqual(#reader:snapshot().commands, #before.commands, "export does not enter the transcript")
local sent
local priorNS = controller.ns
controller.ns = setmetatable({ shareFiles = function(items) sent = items[1]; return true end }, { __index = priorNS })
t.expect(controller:exportSheet(), "the print action shares an HTML file on iOS")
t.assertEqual(sent.name, "character-sheet.html")
t.assertEqual(sent.text, document)
local opened
t.expect(CharacterSheet.share({ openPath = function(path)
	opened = path
	local file = assert(io.open(path, "rb"))
	t.assertEqual(file:read("a"), document, "the macOS print action opens the same HTML")
	file:close()
	return true
end }, sheet), "the macOS print action succeeds")
t.expect(opened:match("%.html$"))
os.remove(opened)

controller.ns = priorNS

os.exit(t.summary() and 0 or 1)
