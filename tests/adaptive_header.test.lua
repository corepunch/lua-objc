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

local function header(buttons)
	return xml.renderFile("apps/diskmap/views/components/PageHeader.etlua", {
		header = {icon = "hammer", color = "blue", title = "Xcode DerivedData"},
		summary = "8.0 GB · ~/Library/Developer/Xcode/DerivedData", buttons = buttons,
	}, ns)
end
local actions = {
	{id = "reveal", title = "Show in Finder", action = "reveal"},
	{id = "open", title = "Open Xcode DerivedData…", action = "open"},
	{id = "remove", title = "Remove from Favorites", action = "remove"},
}
local page, r = header(actions)
resize(page, 2000)
t.expect(below(r.pageHeading, r.pageActions), "three buttons always go below even at wide widths")
t.expect(r.pageHeading.size.height < 100, "stacked heading keeps its intrinsic height")
t.assertEqual(r.pageActions.frame.origin.x, 0, "action row begins at the header leading edge")
resize(page, 350)
t.expect(r.pageActions.size.height > r.reveal.size.height, "long groups wrap into additional rows")
t.expect(below(r.pageHeading, r.pageActions), "wrapped actions remain below the title")
resize(page, 2000)
t.assertEqual(r.pageActions.subviews[1], r.reveal, "wrapping preserves the same button")

actions[3].hidden = true
local pair, p = header(actions)
resize(pair, 2000)
t.expect(not below(p.pageHeading, p.pageActions), "hidden third button is excluded from count")
resize(pair, 500)
t.expect(below(p.pageHeading, p.pageActions), "two long buttons move below at narrow widths")
resize(pair, 2000)
t.expect(not below(p.pageHeading, p.pageActions), "two buttons return inline when their width fits the budget")
p.open.title = "Open a much longer SDK installation and all of its development tools…"
resize(pair, 1000)
t.expect(below(p.pageHeading, p.pageActions), "changed native button titles affect the width decision")
local single, s = header({actions[1]})
resize(single, 1000)
t.expect(not below(s.pageHeading, s.pageActions), "one short action stays inline")
resize(single, 300)
t.expect(below(s.pageHeading, s.pageActions), "one long action also obeys the width budget")
local disabled, d = header({{id = "disabled", title = "Open SDKs…", action = "open", disabled = true}})
resize(disabled, 200)
t.expect(below(d.pageHeading, d.pageActions), "disabled buttons still reserve their native width")
local empty, e = header({})
resize(empty, 500)
t.expect(e.pageActions == nil, "empty headers have no blank action row")
t.expect(e.pageTitle.size.width > 0, "empty actions leave title space intact")
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
