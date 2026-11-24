_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Template = require("ui.template")

local SOURCE = [[<Paragraph id="prose" text="Café — the door opens." design="serif" size="18" revealedCharacters="<%= shown %>">
<% for _, range in ipairs(ranges) do %><Bold location="<%= range.location %>" length="<%= range.length %>" /><% end %>
</Paragraph>]]
local host = xml.render('<VStack />', {}, ns)
local path = os.tmpname()
local file = assert(io.open(path, "w")); file:write(SOURCE); file:close()
local template = Template.new(host, path, ns)
template:update({ shown = -1, ranges = {{ location = 11, length = 4 }} })
local view = template.refs.prose
local function at(offset) return bridge._paragraphAttributes(view, offset) end
t.expect(at(11).bold and at(14).bold, "bold covers the Unicode scalar range")
t.expect(not at(10).bold and not at(15).bold, "adjacent prose stays regular")
t.expect(not at(11).linked, "bold does not add a native link")
t.assertEqual(#bridge._paragraphLinks(view), 0, "bold carries no action menus")
t.assertEqual(view.text, "Café — the door opens.", "formatting preserves selectable text")
view.revealedCharacters = 11
t.expect(at(11).bold and not at(11).visible, "unrevealed text retains bold geometry")
view.revealedCharacters = -1
t.expect(at(11).bold and at(11).visible, "revealing restores ink without losing bold")
template:update({ shown = -1, ranges = {{ location = 0, length = 4 }} })
t.expect(template.refs.prose == view, "changing ranges retains the native paragraph")
t.expect(at(0).bold and not at(11).bold, "changing ranges removes old emphasis")
template:update({ shown = -1, ranges = {} })
t.expect(not at(0).bold, "removing all ranges restores ordinary text")
t.assertEqual(view.text, "Café — the door opens.", "removing emphasis preserves content")
local edge = xml.render([[<Paragraph text="x"><Bold location="8" length="2" /><Bold location="-1" length="2" /><Bold location="0" length="0" /></Paragraph>]], {}, ns)
t.expect(not bridge._paragraphAttributes(edge, 0).bold, "empty and out-of-bounds ranges do nothing")
local mixed = xml.render([[<Paragraph text="bold link"><Bold location="0" length="4" /><Hyperlink location="5" length="4" label="link"><MenuItem title="Act" /></Hyperlink></Paragraph>]], {}, ns)
t.expect(bridge._paragraphAttributes(mixed, 0).bold and not bridge._paragraphAttributes(mixed, 0).linked,
	"formatting remains independent when a paragraph also has links")
t.assertEqual(#bridge._paragraphLinks(mixed), 1, "independent hyperlinks remain supported")
os.remove(path)
os.exit(t.summary() and 0 or 1)
