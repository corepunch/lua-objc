_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local bridge = require("AppKitNative")

-- A paragraph marks the words a reader can act on with <Hyperlink> children
-- (WPF Hyperlink inside a TextBlock); each opens a menu of <MenuItem>s.
local PROSE = "A corroded brass plaque hangs askew on the gate. A path leads north."
local chosen = {}
local function actions()
	return {
		examine = function() table.insert(chosen, "examine plaque") end,
		read = function() table.insert(chosen, "read plaque") end,
		north = function() table.insert(chosen, "north") end,
	}
end
local SOURCE = [[
<VStack spacing="0" alignment="leading">
	<Paragraph id="linked" text="]] .. PROSE .. [[" size="17" design="serif" figure="<%= figure %>" revealedCharacters="<%= revealed %>">
		<% for _, link in ipairs(links) do %>
		<Hyperlink location="<%= link.location %>" length="<%= link.length %>" label="<%= link.label %>">
			<% for _, item in ipairs(link.items) do %>
			<MenuItem title="<%= item.title %>" <% if item.action then %>action="<%= item.action %>"<% end %> disabled="<%= item.disabled and "true" or "false" %>" />
			<% end %>
		</Hyperlink>
		<% end %>
	</Paragraph>
	<Paragraph id="plain" text="]] .. PROSE .. [[" size="17" design="serif" />
</VStack>]]
local LINKS = {
	{ location = 11, length = 12, label = "plaque", items = {
		{ title = "Examine plaque", action = "examine" }, { title = "Read plaque", action = "read" },
		{ title = "Unavailable", disabled = true },
	} },
	{ location = 62, length = 5, label = "north", items = { { title = "Go north", action = "north" } } },
}

local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w"))
file:write(SOURCE)
file:close()
local host = ns.VStack {}
local template = Template.new(host, path, ns)
local _, refs = template:update({ links = LINKS, figure = "", revealed = -1, actions = actions() })
host.size = ns.Size(320, 2000); host:layout(320)

local links = bridge._paragraphLinks(refs.linked)
t.assertEqual(#links, 2, "each <Hyperlink> becomes a link")
t.assertEqual(links[1].text, "brass plaque", "a link covers the characters it names")
t.assertEqual(links[2].text, "north", "a later link covers its own words")
t.assertEqual(links[1].label, "plaque", "a link keeps its label")
t.assertEqual(#links[1].titles, 3, "a link lists its menu items")
t.assertEqual(links[1].titles[2], "Read plaque", "menu items keep their order")
t.expect(links[1].revealed, "a link in fully shown text can be tapped")
t.expect(links[1].inked and links[2].inked, "linked words take their rule's colour")
t.assertEqual(refs.linked.text, PROSE, "links leave the paragraph's text alone")
t.assertEqual(refs.linked.size.height, refs.plain.size.height, "links do not change how the text is set")
t.assertEqual(#bridge._paragraphLinks(refs.plain), 0, "a paragraph without children has no links")

bridge._paragraphPerformLink(refs.linked, 1, 2)
bridge._paragraphPerformLink(refs.linked, 2, 1)
t.assertEqual(table.concat(chosen, ","), "read plaque,north", "choosing a menu item runs its action")
bridge._paragraphPerformLink(refs.linked, 1, 3)
t.assertEqual(#chosen, 2, "an item without an action does nothing")
t.assertThrows(function() bridge._paragraphPerformLink(refs.linked, 3, 1) end, "a missing link is an error")
t.assertThrows(function() bridge._paragraphPerformLink(refs.linked, 1, 4) end, "a missing item is an error")

-- A typewriter reveal: a link can be tapped once typing has reached it.
local view = refs.linked
view.revealedCharacters = 5
links = bridge._paragraphLinks(view)
t.expect(not links[1].revealed and not links[2].revealed, "links wait hidden until typing reaches them")
t.expect(not links[1].inked, "an untyped link waits uninked")
view.revealedCharacters = 12
links = bridge._paragraphLinks(view)
t.expect(links[1].revealed and not links[2].revealed, "a link is live from its first typed character")
view.revealedCharacters = -1

-- New links reach the same native view in place.
local _, updated = template:update({ links = { LINKS[2] }, figure = "", revealed = -1, actions = actions() })
t.expect(updated.linked == view, "changing links keeps the paragraph's native view")
links = bridge._paragraphLinks(view)
t.assertEqual(#links, 1, "removed links are gone")
t.assertEqual(links[1].text, "north", "the remaining link keeps its range")
bridge._paragraphPerformLink(view, 1, 1)
t.assertEqual(chosen[#chosen], "north", "the remaining link still runs its action")
_, updated = template:update({ links = {}, figure = "", revealed = -1, actions = actions() })
t.assertEqual(#bridge._paragraphLinks(updated.linked), 0, "a paragraph can lose every link")

-- A figure moves the lines, never the words: links keep their ranges.
_, updated = template:update({ links = LINKS, figure = "apps/adventure-arena/assets/zork1.jpg", revealed = -1, actions = actions() })
host:layout(320)
t.expect(updated.linked.figureView ~= nil, "the paragraph floats its figure")
links = bridge._paragraphLinks(updated.linked)
t.assertEqual(links[1].text, "brass plaque", "a link beside the figure covers its words")
local first = { { location = 0, length = 10, label = "corroded", items = { { title = "Examine", action = "examine" } } } }
_, updated = template:update({ links = first, figure = "apps/adventure-arena/assets/zork1.jpg", revealed = -1, actions = actions() })
t.assertEqual(bridge._paragraphLinks(updated.linked)[1].text, "A corroded", "a link at the first character starts there")

-- Edge cases: ranges beyond the text, empty ranges, other children.
local edge = { { location = 62, length = 500, label = "tail", items = {} }, { location = 900, length = 4, label = "gone", items = {} },
	{ location = 3, length = 0, label = "empty", items = {} } }
_, updated = template:update({ links = edge, figure = "", revealed = -1, actions = actions() })
links = bridge._paragraphLinks(updated.linked)
t.assertEqual(links[1].text, "north.", "a link running past the end stops at the end")
t.assertEqual(links[2].text, "", "a link beyond the text covers nothing")
t.assertEqual(links[3].text, "", "an empty link covers nothing")
t.assertThrows(function()
	xml.render([[<Paragraph text="x"><Label text="y" /></Paragraph>]], {}, ns)
end, "a paragraph accepts only Hyperlink children")

-- Characters are counted as utf8.len counts them.
local accented = xml.render([[<Paragraph text="Café — the door is open.">
	<Hyperlink location="11" length="4" label="door"><MenuItem title="Open door" action="examine" /></Hyperlink>
</Paragraph>]], { actions = actions() }, ns)
t.assertEqual(bridge._paragraphLinks(accented)[1].text, "door", "link ranges count characters, not bytes")

template:dispose()
os.remove(path)
os.exit(t.summary() and 0 or 1)
