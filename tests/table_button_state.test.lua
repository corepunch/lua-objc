_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local pressed
local list = xml.render([[
<List onColumnButton="flag">
  <Column id="name" />
  <Column id="review" buttonSymbol="flag" imageKey="symbol" helpKey="help" enabledKey="allowed" width="32" />
</List>]], {actions = {flag = function(_, column, row) pressed = row.id end}}, ns)
list:replaceRows({{id = "a", name = "A", symbol = "flag", help = "Flag A for review", allowed = true},
	{id = "b", name = "B", symbol = "flag.fill", help = "Remove review flag from B", allowed = false}})
local first = bridge._tableCell(list, 1, 0).actionButton
local second = bridge._tableCell(list, 1, 1).actionButton
t.expect(first.image ~= nil and second.image ~= nil, "each row resolves its SF Symbol")
t.assertEqual(first.accessibilityLabel, "Flag A for review", "the button names its action for VoiceOver")
t.assertEqual(second.toolTip, "Remove review flag from B", "a marked row explains the reverse action")
t.expect(first.enabled and not second.enabled, "row enabledKey controls the real native button")
bridge._pressColumnButton(list, 1, 0)
t.assertEqual(pressed, "a", "the action receives the clicked item")
list:replaceRows({{id = "c", name = "C", symbol = "flag.fill", help = "Remove review flag from C", allowed = true}})
local replaced = bridge._tableCell(list, 1, 0).actionButton
t.assertEqual(replaced.accessibilityLabel, "Remove review flag from C", "replaced rows update their action label")
t.expect(replaced.enabled, "a reused disabled button becomes enabled")
os.exit(t.summary() and 0 or 1)
