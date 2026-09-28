_G.__headless = true
local ns = require("AppKit")
local xml = require("ui.xml")
local t = require("TestKit")

-- fixedSize="vertical": SwiftUI `.fixedSize(horizontal: false, vertical: true)`.
-- A row of panels takes its tallest panel's height, its maxHeight="infinity"
-- panels stretch to match, and the window's spare height goes elsewhere.
local template = [[
<VStack id="root" spacing="10">
	<VStack id="stage" maxWidth="infinity" maxHeight="infinity" />
	<HStack id="row" spacing="8" alignment="top" maxWidth="infinity"<% if fixed then %> fixedSize="<%= fixed %>"<% end %>>
		<VStack id="tall" width="100" height="120" />
		<VStack id="short" maxHeight="infinity" maxWidth="infinity">
			<VStack width="50" height="40" />
		</VStack>
	</HStack>
</VStack>]]

local function height(view) return view.frame.size.height end

local function measure(fixed, height)
	local root, refs = xml.render(template, {fixed = fixed}, ns)
	root.size = ns.Size(400, height)
	root:layout(400)
	return refs
end

local refs = measure("vertical", 500)
local rowHeight, shortHeight, stageHeight = height(refs.row), height(refs.short), height(refs.stage)
t.assertEqual(rowHeight, 120, "a vertically fixed row keeps its tallest child's height")
t.assertEqual(shortHeight, 120, "a filling child stretches to the row, not the window")
t.assertEqual(stageHeight, 500 - 10 - 120, "the spare height goes to the flexible sibling")

local grown = measure("vertical", 800)
t.assertEqual((height(grown.row)), 120, "a taller window leaves the fixed row alone")
t.assertEqual((height(grown.stage)), 800 - 10 - 120, "and grows the stage")

local shrunk = measure("vertical", 200)
t.assertEqual((height(shrunk.row)), 120, "a fixed row does not shrink with the window")

-- Without fixedSize the filling child makes the row share the spare height
-- with the stage, which is the mismatch fixedSize exists to avoid.
local flexible = measure(nil, 500)
t.expect((height(flexible.row)) > 120, "an unfixed row with a filling child grows")
local both = measure("both", 500)
t.assertEqual((height(both.row)), 120, "both fixes the vertical axis too")
local root = xml.render('<HStack fixedSize="horizontal"><VStack maxWidth="infinity" height="10" /></HStack>', {}, ns)
t.assertEqual(root.fixedSize, "horizontal", "fixedSize reaches the native view")
t.assertThrows(function() xml.render('<HStack fixedSize="sideways" />', {}, ns) end,
	"unknown fixedSize axes are rejected")

os.exit(t.summary() and 0 or 1)
