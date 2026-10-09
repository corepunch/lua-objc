_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local root, refs = xml.render([[
<VStack spacing="0" maxWidth="infinity">
  <HStack id="header" alignment="leading" spacing="14" maxWidth="infinity" trailingMaxWidthFraction="0.3">
    <VStack id="heading" flexGrow="1" maxWidth="infinity"><Label text="Heading"/></VStack>
    <VStack id="actions" width="300" height="24"/>
  </HStack>
  <Label id="after" text="After"/>
</VStack>]], {}, ns)
local function resize(view, width)
	view.size = ns.Size(width, 250)
	view:layout(width)
end
local function below(heading, actions)
	return actions.frame.origin.y + actions.size.height <= heading.frame.origin.y
end
resize(root, 1000)
t.expect(not below(refs.heading, refs.actions), "exactly 30 percent stays inline")
t.expect(refs.actions.frame.origin.x > refs.heading.frame.origin.x, "inline controls follow the heading")
resize(root, 999)
t.expect(below(refs.heading, refs.actions), "more than 30 percent moves below")
t.assertEqual(refs.heading.size.width, 999, "stacked heading gets full width")
t.assertEqual(refs.actions.frame.origin.x, 0, "stacked actions align with the leading edge")
t.expect(refs.after.frame.origin.y + refs.after.size.height <= refs.header.frame.origin.y, "following content clears the taller header")
resize(root, 1000)
t.expect(not below(refs.heading, refs.actions), "widening restores inline layout")
t.assertEqual(refs.header.subviews[2], refs.actions, "resizing preserves the native controls")
refs.actions.hidden = true
resize(root, 100)
t.expect(refs.header.size.height < 40, "hidden actions do not force another row")
refs.actions.hidden = false
resize(root, 0)
t.expect(refs.header.size.height >= 0, "zero width remains finite")
resize(root, 1000)
t.expect(not below(refs.heading, refs.actions), "zero width round trip restores inline layout")
refs.header.trailingMaxWidthFraction = 0
resize(root, 400)
t.expect(not below(refs.heading, refs.actions), "zero disables adaptive layout")

-- Diskmap headers reserve no space for operations; the native toolbar owns them.
local page, refs = xml.renderFile("apps/diskmap/views/components/PageHeader.etlua", {
	header = {icon = "hammer", color = "systemBlue", title = "Xcode DerivedData"},
	summary = "8.0 GB · ~/Library/Developer/Xcode/DerivedData",
}, ns)
for _, width in ipairs({350, 1000, 2000, 350}) do
	resize(page, width)
	t.assertEqual(refs.pageActions, nil, "headers have no inline operation row at " .. width)
	t.expect(refs.pageTitle.size.width > 0, "the title keeps usable width at " .. width)
	t.expect(page.fittingSize.height < 100, "the header keeps its concise intrinsic height at " .. width)
end
-- Retained changes patch the property in place, including its removal.
local Template = require("ui.template")
local path = os.tmpname() .. ".etlua"
local file = assert(io.open(path, "w"))
file:write([[<HStack id="header" spacing="14"<% if fraction then %> trailingMaxWidthFraction="<%= fraction %>"<% end %>><Label text="Heading"/><Button id="action" title="Open Xcode DerivedData…"/></HStack>]])
file:close()
local host = xml.render('<VStack maxWidth="infinity"/>', {}, ns)
local template = Template.new(host, path, ns)
local first, a = template:update({fraction = 0.3})
local same, b = template:update({fraction = 0.5})
t.assertEqual(same, first, "changing the threshold preserves the native header")
t.assertEqual(b.action, a.action, "changing the threshold preserves its button")
t.assertEqual(same.trailingMaxWidthFraction, 0.5, "retained threshold update applies")
local removed, c = template:update({})
t.assertEqual(removed, first, "removing the threshold keeps the header")
t.assertEqual(c.action, a.action, "removing the threshold keeps the button")
t.assertEqual(removed.trailingMaxWidthFraction, 0, "removed property resets to disabled")
template:dispose()
os.remove(path)
os.exit(t.summary() and 0 or 1)
