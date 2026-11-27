-- The offline translator: the en-ru-translator submodule as a service and
-- the one page driven as a person would (type, see it translated, copy, clear).
_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local bridge = require("AppKitNative")
local Translator = require("apps.translator.services.Translator")

local engine = Translator.new({ readFile = false })

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
t.expect(app.sidebar == nil, "a one-page app has no sidebar")
t.assertEqual(window.title, "English → Russian", "the languages are the window's title")
t.assertEqual(window.subtitle, "Translates as you type", "with what happens as its subtitle")
bridge._appkitLayout(window)
local refs = app.refs
local actions = app:actions()

-- Two halves of the window: the editor on top, the read-only translation
-- below, the same height whatever they hold.
t.expect(refs.english ~= nil and refs.russian ~= nil, "the page has an editor and a translation")
t.assertEqual(refs.russian.documentView.editable, false, "the translation is read-only")
t.assertEqual(refs.russian.documentView.selectable, true, "but can be selected")
t.assertEqual(refs.english.documentView.placeholder, "Enter text", "the empty editor prompts for text")
t.expect(refs.clear == nil and refs.copy == nil, "Clear and Copy are not in the page")
local function halves() -- heights of the page's two halves
	local heights = {}
	for _, view in ipairs({ app.refs.english, app.refs.russian or app.refs.failure }) do
		local half = view
		while half.superview and half.superview ~= app.content.subviews[1] do half = half.superview end
		table.insert(heights, half.frame.size.height)
	end
	return heights
end
local before = halves()
t.expect(before[1] > 0, "the halves have height")
t.assertEqual(before[1], before[2], "the editor and the translation split the height equally")
local function windowX(view) -- a view's leading edge in its window
	local x = 0
	while view do x, view = x + view.frame.origin.x, view.superview end
	return x
end
t.assertEqual(windowX(refs.english), windowX(refs.russian), "English and Russian text start on one leading edge")

-- The window toolbar's Clear and Copy act on the page and ask it whether
-- they are enabled.
t.assertEqual(actions.canTool_clear(), false, "Clear is dimmed with nothing typed")
t.assertEqual(actions.canTool_copy(), false, "Copy is dimmed with nothing translated")

-- Typing translates as it goes; the editor is kept, not rebuilt.
local editor = refs.english
local russian = refs.russian
ns._textEditorTestInput(editor, "She was here.")
t.assertEqual(app.pages.translate.text, "She was here.", "each keystroke reaches the page")
t.assertEqual(app.refs.russian.text, "Она была здесь.", "and is translated at once")
t.expect(app.refs.failure == nil, "successful diagnostics do not render an error")
t.expect(app.refs.english == editor and app.refs.russian == russian, "neither half is rebuilt")
bridge._appkitLayout(window)
local after = halves()
t.assertEqual(after[1], before[1], "typing does not resize the editor")
t.assertEqual(after[2], before[2], "or the translation")
t.assertEqual(actions.canTool_clear(), true, "Clear is enabled once there is text")
t.assertEqual(actions.canTool_copy(), true, "and Copy once there is a translation")
actions.tool_copy()
t.assertEqual(copied[1], "Она была здесь.", "Copy puts the translation on the pasteboard")

ns._textEditorTestInput(editor, "I am home.")
t.assertEqual(app.refs.russian.text, "Я дома.", "the next keystroke replaces it")
t.expect(app.refs.english == editor and app.refs.russian == russian, "in place")

ns._textEditorTestInput(editor, "I’m flying home.")
t.assertEqual(app.refs.russian.text, "Я лечу домой.", "smart keyboard punctuation reaches the engine correctly")
t.assertEqual(editor.text, "I’m flying home.", "translation preserves the user's original editor text")
actions.tool_copy()
t.assertEqual(copied[2], "Я лечу домой.", "Copy receives the corrected translation")
ns._textEditorTestInput(editor, "I’m flying ho")
t.expect(type(app.refs.russian.text) == "string", "partial input still translates")
t.expect(app.refs.failure == nil and app.refs.english == editor, "partial input keeps the editor and shows no error")

actions.tool_clear()
t.assertEqual(editor.text, "", "Clear empties the editor")
t.assertEqual(app.refs.russian.text, "", "and the translation")
t.assertEqual(actions.canTool_clear(), false, "and dims itself")
t.assertEqual(actions.canTool_copy(), false, "and Copy")
actions.tool_copy()
t.assertEqual(#copied, 2, "Copy with nothing translated copies nothing")

-- A failing engine says why instead of translating.
app.pages.translate.app = { translator = { translate = function() return nil, "no rule" end }, clipboard = {} }
ns._textEditorTestInput(editor, "x")
t.assertEqual(app.refs.failure.text, "no rule", "the engine's message shows")
t.expect(app.refs.russian == nil, "in place of a translation")

os.exit(t.summary() and 0 or 1)
