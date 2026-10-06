-- The offline translator: the en-ru-translator submodule as a service and
-- the one page driven as a person would (type, see it translated, copy, clear).
_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local bridge = require("AppKitNative")
local Translator = require("apps.translator.services.Translator")

-- The service, reading its files through a reader as it does on iOS.
local reads = {}
local diskOpen = io.open
local function readFile(path)
	table.insert(reads, path)
	local file = assert(diskOpen(path, "rb"))
	local body = file:read("a")
	file:close()
	return body
end
local engine = Translator.new({ readFile = readFile })
t.expect(not engine:isLoaded(), "the dictionaries are not loaded until the first translation")
t.assertEqual(engine:translate("The weather is good today."), "Погода хорошая сегодня.", "a sentence translates")
t.expect(engine:isLoaded(), "and then they are")
t.expect(#reads >= 2 and reads[1]:find("^apps/translator/en%-ru%-translator/data/") ~= nil,
	"the dictionaries are read through the platform's reader")
t.assertEqual(engine:translate("Hello.\n\nWhere is the station"), "Привет.\n\nГде станция",
	"each line translates alone and the breaks are kept")
t.assertEqual(engine:translate(""), "", "nothing translates to nothing")
t.assertEqual(engine:translate("Xyzzy."), "Xyzzy.", "an unknown word passes through")
local open, path = io.open, package.path
engine:translate("Hello.")
t.expect(io.open == open and package.path == path, "io.open and package.path are restored after a call")
-- On AppKit the files are on disk.
t.assertEqual(Translator.new({ readFile = false }):translate("Hello."), "Привет.", "the service reads from disk without a reader")

-- Typing changes one line: the others come from the previous call.
local counting = Translator.new({ readFile = false })
counting.engine = { translate = function(_, line) counting.calls = (counting.calls or 0) + 1; return "<" .. line .. ">" end }
counting:translate("one\ntwo")
counting.calls = 0
t.assertEqual(counting:translate("one\ntwo!"), "<one>\n<two!>", "the text is translated line by line")
t.assertEqual(counting.calls, 1, "only the changed line goes to the engine")

-- The app's own services come from Services.lua beside app.xml.
local launched = dofile("apps/translator/init.lua").new({ args = {} })
t.expect(launched.services.translator ~= nil and launched.services.clipboard ~= nil,
	"the launcher hands the page the services Services.lua builds")

-- The page, with a pasteboard that records what it was given.
local copied = {}
local App = dofile("apps/translator/init.lua")
local app = App.new({ args = {}, services = {
	translator = engine,
	clipboard = { copy = function(text) table.insert(copied, text) end },
} })
local window = app:createWindow()
bridge._appkitLayout(window)
local refs = app.refs
t.expect(refs.english ~= nil and refs.russian == nil, "the page has an editor and no result yet")
t.assertEqual(refs.clear.hidden, true, "Clear is hidden while there is nothing to clear")

-- Typing translates as it goes; the editor is kept, not rebuilt.
local editor = refs.english
ns._textEditorTestInput(editor, "She can speak Russian.")
t.assertEqual(app.pages.translate.text, "She can speak Russian.", "each keystroke reaches the page")
t.assertEqual(app.refs.russian.text, "Она может говорить русского.", "and is translated at once")
t.expect(app.refs.english == editor, "the editor survives the page being drawn again")
t.assertEqual(app.refs.clear.hidden, false, "Clear shows")
t.expect(app.refs.copy ~= nil, "with a Copy button")
app.page.actions.copy()
t.assertEqual(copied[1], "Она может говорить русского.", "Copy puts the translation on the pasteboard")

ns._textEditorTestInput(editor, "Hello.")
t.assertEqual(app.refs.russian.text, "Привет.", "the next keystroke replaces it")
t.expect(app.refs.english == editor and app.refs.russian ~= nil, "in place")

app.page.actions.clear()
t.assertEqual(editor.text, "", "Clear empties the editor")
t.expect(app.refs.russian == nil and app.refs.copy == nil, "and removes the result")

-- A failing engine says why instead of translating.
app.pages.translate.app = { translator = { translate = function() return nil, "no rule" end }, clipboard = {} }
ns._textEditorTestInput(editor, "x")
t.assertEqual(app.refs.failure.text, "no rule", "the engine's message shows")
t.expect(app.refs.russian == nil, "in place of a translation")

os.exit(t.summary() and 0 or 1)
