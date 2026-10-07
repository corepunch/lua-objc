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
t.assertEqual(engine:translate(" \n\t"), "", "empty input needs no assets")
t.expect(not engine:isLoaded() and #reads == 0, "empty input keeps the engine unloaded")
local translated, failure = engine:translate("The weather is good today.")
t.assertEqual(translated, "Погода хорошая сегодня.", "a sentence translates")
t.assertEqual(failure, nil, "the engine's diagnostic state is not a page error")
t.expect(engine:isLoaded(), "and then they are")
t.assertEqual(#reads, 3, "the three runtime assets are read through the platform's reader")
t.assertEqual(reads[1], "apps/translator/data/LTPRO.EXE", "executable tables come from the bundled data")
t.assertEqual(engine:translate("Hello.\n\nWhere is the station"), "Привет.\n\nГде - станция",
	"each line translates alone and the breaks are kept")
t.assertEqual(engine:translate(""), "", "nothing translates to nothing")
t.assertEqual(engine:translate("Xyzzy."), "Xyzzy.", "an unknown word passes through")
for _, apostrophe in ipairs({ "'", "’", "‘" }) do
	t.assertEqual(engine:translate("I" .. apostrophe .. "m testing this."), "Я тестирую это.",
		"the contraction translates with straight or smart apostrophes")
end
for input, expected in pairs({
	["He’s testing this."] = "Он тестирует это.",
	["You’re testing this."] = "Вы тестируете это.",
	["We’ve tested this."] = "Мы протестировали это.",
	["I’ll test this."] = "Я протестирую это.",
	["I’d test this."] = "Я протестирую это.",
	["I don’t test this."] = "Я не тестирую это.",
	["I can’t test this."] = "Я не могу протестировать это.",
	["I won’t test this."] = "Я не протестирую это.",
	["I shan’t test this."] = "Я не протестирую это.",
	["There’s a book."] = "Есть книга.",
	["John’s book."] = "Книга Джона.",
}) do
	t.assertEqual(engine:translate(input), expected, "the native contraction table handles " .. input)
end
local open, path = io.open, package.path
engine:translate("Hello.")
t.expect(io.open == open and package.path == path, "io.open and package.path are restored after a call")
t.assertEqual(#reads, 3, "later sentences reuse the asset bytes")
-- On AppKit the files are on disk.
t.assertEqual(Translator.new({ readFile = false }):translate("Hello."), "Привет.", "the service reads from disk without a reader")

-- Typing changes one line: the others come from the previous call.
local counting = Translator.new({ readFile = false })
counting.engine = { translate = function(line) counting.calls = (counting.calls or 0) + 1; return "<" .. line .. ">" end }
counting:translate("one\ntwo")
counting.calls = 0
t.assertEqual(counting:translate("one\ntwo!"), "<one>\n<two!>", "the text is translated line by line")
t.assertEqual(counting.calls, 1, "only the changed line goes to the engine")

-- Upstream throws for unsupported branches; the page receives a message.
counting.engine.translate = function() error("unsupported lexical branch", 0) end
local failedText, message = counting:translate("bad")
t.assertEqual(failedText, nil, "engine errors do not escape the service")
t.assertEqual(message, "unsupported lexical branch", "the error reaches the page")
t.expect(io.open == open and package.path == path, "a failed translation restores global IO and module paths")
t.assertEqual(counting.lines["one"], "<one>", "failure preserves the previous successful line cache")
local missing = Translator.new({ readFile = function() return nil, "missing asset" end })
failedText, message = missing:translate("Hello.")
t.expect(failedText == nil and message:find("LTPRO.EXE", 1, true) ~= nil, "missing assets are reported")
t.expect(not missing:isLoaded(), "a failed asset load can be retried")
t.expect(io.open == open and package.path == path, "a failed asset load restores global state")

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
t.assertEqual(app.refs.russian.text, "Она может сказать Русского.", "and is translated at once")
t.expect(app.refs.failure == nil, "successful diagnostics do not render an error")
t.expect(app.refs.english == editor, "the editor survives the page being drawn again")
t.assertEqual(app.refs.clear.hidden, false, "Clear shows")
t.expect(app.refs.copy ~= nil, "with a Copy button")
app.page.actions.copy()
t.assertEqual(copied[1], "Она может сказать Русского.", "Copy puts the translation on the pasteboard")

ns._textEditorTestInput(editor, "Hello.")
t.assertEqual(app.refs.russian.text, "Привет.", "the next keystroke replaces it")
t.expect(app.refs.english == editor and app.refs.russian ~= nil, "in place")

ns._textEditorTestInput(editor, "I’m testing this.")
t.assertEqual(app.refs.russian.text, "Я тестирую это.", "smart keyboard punctuation reaches the engine correctly")
t.assertEqual(editor.text, "I’m testing this.", "translation preserves the user's original editor text")
app.page.actions.copy()
t.assertEqual(copied[2], "Я тестирую это.", "Copy receives the corrected translation")

app.page.actions.clear()
t.assertEqual(editor.text, "", "Clear empties the editor")
t.expect(app.refs.russian == nil and app.refs.copy == nil, "and removes the result")

-- A failing engine says why instead of translating.
app.pages.translate.app = { translator = { translate = function() return nil, "no rule" end }, clipboard = {} }
ns._textEditorTestInput(editor, "x")
t.assertEqual(app.refs.failure.text, "no rule", "the engine's message shows")
t.expect(app.refs.russian == nil, "in place of a translation")

os.exit(t.summary() and 0 or 1)
