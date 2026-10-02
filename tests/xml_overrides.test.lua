-- A page whose structure is fixed and whose values come from its model sets
-- text, visibility and enabled state by node id in template data.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local root, refs = xml.render([[<VStack>
	<Label id="summary" text="before" />
	<Button id="go" title="Go" action="go" />
	<Label id="gone" text="shown" />
	<Button id="off" title="Off" action="go" />
</VStack>]], {
	overrides = { texts = { summary = "3 files", go = "Mark 3 Files" }, hidden = { gone = true }, disabled = { off = true } },
	actions = { go = function() end },
}, ns)
t.assertEqual(refs.summary.text, "3 files", "texts sets a label's text by id")
t.assertEqual(refs.go.title, "Mark 3 Files", "and a button's title")
t.expect(refs.gone.hidden, "hidden hides a node by id")
t.expect(not refs.off.enabled, "disabled disables it")
local plain, plainRefs = xml.render('<Label id="summary" text="before" />', {}, ns)
t.assertEqual(plain.text, "before", "without overrides the template says it")
os.exit(t.summary() and 0 or 1)
