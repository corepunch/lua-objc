-- A retained template renders with the resources its owner gives it: the
-- language is chosen where the template renders, and a language change shows
-- on the next update without the caller naming the words again.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Template = require("ui.template")
local Resources = require("ui.resources")
local xml = require("ui.xml")

local stub = os.tmpname()
local path = stub .. ".etlua"
local file = assert(io.open(path, "w"))
file:write([[<VStack>
	<Label id="static" text="@greeting" />
	<Label id="formatted" text="<%= string.format(resources.hello, name) %>" />
</VStack>]])
file:close()

local function words(greeting, hello)
	return Resources.fromNodes(xml.parse(string.format(
		'<Resources><String id="greeting" value="%s" /><String id="hello" value="%s" /></Resources>', greeting, hello)))
end
local english, german = words("Hi", "Hello, %s"), words("Hallo", "Guten Tag, %s")
local current, asked = english, 0
local template = Template.new(ns.VStack(), path, ns, function() asked = asked + 1; return current end)
local _, refs = template:update({ name = "Igor" })
t.assertEqual(refs.static.text, "Hi", "an update takes the owner's resources")
t.assertEqual(refs.formatted.text, "Hello, Igor", "and so does the template's own code")

current = german
_, refs = template:update({ name = "Igor" })
t.assertEqual(refs.static.text, "Hallo", "a language change shows on the next update")
t.assertEqual(refs.formatted.text, "Guten Tag, Igor")

local before = refs.static
_, refs = template:update({ name = "Igor" })
t.expect(refs.static == before, "an update with the same words and data keeps its views")

_, refs = template:update({ name = "Igor", resources = english })
t.assertEqual(refs.static.text, "Hi", "an update's own resources win")

local plain = Template.new(ns.VStack(), path, ns)
t.assertThrows(function() plain:update({ name = "x" }) end, "without resources the template has none to format with")
template:dispose()
plain:dispose()
os.remove(path)
os.remove(stub)
os.exit(t.summary() and 0 or 1)
