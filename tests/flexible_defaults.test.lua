_G.__headless = true
-- Views SwiftUI makes flexible without a frame modifier take the width they
-- are offered here too, so templates need no maxWidth="infinity" for them.
-- A stack is flexible when any child is (see implicit_layout.test.lua); the
-- controls below are the children that make it so.
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local WIDTH = 480

local function render(source)
	local root, refs = xml.render(source, {}, ns)
	root.size = ns.Size(WIDTH, 600); root:layout(WIDTH)
	return root, refs
end

-- GroupBox takes the offered width and the height of its content.
local _, box = render([[
<VStack alignment="leading" spacing="0">
	<GroupBox id="box"><Label text="Short" /></GroupBox>
	<GroupBox id="fixed" width="200"><Label text="Short" /></GroupBox>
</VStack>]])
t.assertEqual(box.box.size.width, WIDTH, "GroupBox fills the offered width")
t.expect(box.box.size.height < 100, "GroupBox keeps the height of its content")
t.assertEqual(box.fixed.size.width, 200, "an explicit width wins over the GroupBox default")

-- A vertical ScrollView with a flex basis is still flexible across.
local _, scroll = render([[
<VStack spacing="0">
	<ScrollView id="page" vertical="true" flexGrow="1" flexBasis="0" flexShrink="1">
		<VStack alignment="leading"><Label text="Row" /></VStack>
	</ScrollView>
</VStack>]])
t.assertEqual(scroll.page.size.width, WIDTH, "a ScrollView with a basis fills the cross axis")
t.assertEqual(scroll.page.size.height, 600, "a ScrollView with a basis grows along the main axis")

-- Linear progress fills; the spinner keeps its own size.
local _, bars = render([[
<VStack alignment="leading" spacing="0">
	<Gauge id="gauge" value="0.4" />
	<ProgressView id="bar" value="0.4" />
	<ProgressView id="spinner" />
</VStack>]])
t.assertEqual(bars.gauge.size.width, WIDTH, "a linear Gauge fills the offered width")
t.assertEqual(bars.bar.size.width, WIDTH, "a determinate ProgressView fills the offered width")
t.expect(bars.spinner.size.width < 100, "a spinner keeps its intrinsic width")

-- A row of a Gauge and a Label: the Gauge takes what the Label leaves.
local _, row = render([[
<HStack id="row" spacing="8">
	<Label id="title" text="Title" />
	<Gauge id="gauge" value="0.4" />
</HStack>]])
t.assertEqual(row.row.size.width, WIDTH, "a stack inherits the Gauge's flexibility")
t.assertEqual(row.title.size.width + row.gauge.size.width + 8, WIDTH, "the Gauge takes the remaining width")

-- DisclosureGroup spans the offered width, so its whole header row is a target.
local _, disclosure = render([[
<VStack alignment="leading" spacing="0">
	<DisclosureGroup id="group" label="Details"><Label text="Body" /></DisclosureGroup>
</VStack>]])
t.assertEqual(disclosure.group.size.width, WIDTH, "DisclosureGroup fills the offered width")

-- Text and stacks of text still hug.
local _, hug = render([[
<VStack alignment="leading" spacing="0">
	<Label id="text" text="Hugs" />
	<HStack id="stack"><Label text="Also hugs" /></HStack>
</VStack>]])
t.expect(hug.text.size.width < 100, "a Label hugs its text")
t.expect(hug.stack.size.width < 200, "a stack of text hugs its content")

-- A chart and a tab view take the offered width; a basis names only the main axis.
local _, wide = render([[
<VStack alignment="leading" spacing="0">
	<Treemap id="map" height="120"><TreemapNode id="a" value="3" color="systemBlue" label="A" /></Treemap>
	<TabView id="tabs" flexGrow="1" flexBasis="0" flexShrink="1">
		<Tab title="One"><Label text="One" /></Tab>
	</TabView>
</VStack>]])
t.assertEqual(wide.map.size.width, WIDTH, "a Treemap fills the offered width")
t.assertEqual(wide.tabs.size.width, WIDTH, "a TabView with a basis fills the cross axis")

local _, search = render([[
<VStack spacing="0" padding="16">
	<SearchField id="search" placeholder="Search" />
</VStack>]])
t.assertEqual(search.search.size.width, WIDTH - 32, "a SearchField fills the offered width")
