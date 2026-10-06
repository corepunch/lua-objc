-- <TextEditor onChange>: SwiftUI's TextEditor(text:) for a page. Each edit
-- reaches the action; drawing the page again with the text the editor
-- already shows keeps the same view (and its caret); a new text is set in
-- place, without telling the action about its own write.
_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local Template = require("ui.template")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p " .. dir)
local path = dir .. "/Editor.etlua"
local file = assert(io.open(path, "w"))
file:write('<VStack><TextEditor id="editor" text="<%= text %>" onChange="edit" accessibilityLabel="Notes" /></VStack>')
file:close()

local host = ns.VStack({})
local template = Template.new(host, path, ns)
local edits = {}
local state = { text = "" }
local function draw()
	template:update({ text = state.text, actions = { edit = function(text)
		table.insert(edits, text)
		state.text = text
		draw()
	end } })
end
draw()
local editor = template.refs.editor
t.expect(editor ~= nil, "the editor is a ref")
t.assertEqual(editor.documentView.accessibilityLabel, "Notes", "the editor carries its accessibility label")

ns._textEditorTestInput(editor, "Hello")
t.assertEqual(edits[1], "Hello", "an edit reaches the action")
t.expect(template.refs.editor == editor, "drawing the typed text again keeps the editor")
t.assertEqual(editor.text, "Hello", "and its text")

state.text = "Replaced"
draw()
t.expect(template.refs.editor == editor, "a new text is set in place")
t.assertEqual(editor.text, "Replaced", "the editor shows it")
t.assertEqual(#edits, 1, "a write from the page is not an edit")

state.text = ""
draw()
t.assertEqual(editor.text, "", "an empty text clears the editor")
t.assertEqual(#edits, 1, "still without an edit")

template:dispose()
os.remove(path)
os.remove(dir)
os.exit(t.summary() and 0 or 1)
