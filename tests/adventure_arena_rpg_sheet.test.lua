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
local setupActions
local render = controller.renderTemplate
controller.renderTemplate = function(template, data)
	if template == "sheets/CharacterSetup" then setupActions = data.actions end
	return render(template, data)
end
controller.presentSheet = function(sheet) return sheet end
controller.dismissSheet = function() end
t.expect(controller:show(id, true), "the book opens its generic setup")
local reader = controller.model
t.expect(setupActions and not controller.refs and not reader.engine, "no reader or GO before confirmation")
t.expect(not SavedGames:find(id), "preview is not an autosave")
t.expect(not setupActions.confirm(), "confirmation without a hero is refused")
setupActions.pick_1()
setupActions.pick_2()
setupActions.nameChanged("Алёна <Гром> & дочь")
t.expect(setupActions.confirm(), "confirming starts the mission")
t.assertEqual(reader.entries[1].kind, "banner", "the Russian release line is parsed as a banner")
t.assertEqual(reader.moves, 0, "the mission begins at turn zero")
t.expect(reader.engine:canExportSheet(), "confirmation enables the character sheet")
t.expect(controller.refs.exportSheet ~= nil, "the print action appears in the normal reader")
t.expect(not reader.entries[2] or not reader.entries[2].text or not reader.entries[2].text:find("Выберите героя", 1, true), "profile choices are not part of the story transcript")
t.assertEqual(SavedGames:find(id).setup.id, "arc", "confirmed profile persists at turn zero")
t.assertEqual(#SavedGames:find(id).commands, 0, "setup leaves no parser commands")
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
