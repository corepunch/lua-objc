_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local root, refs = xml.render([[
<SafeAreaInset id="inset" edge="bottom">
	<ScrollView id="content">
		<VStack><Label text="Scrollable content" /></VStack>
	</ScrollView>
	<VStack id="accessory" height="60" background="secondaryBackground">
		<Label text="Persistent action" />
	</VStack>
</SafeAreaInset>]], {}, ns)

root.size = ns.Size(320, 600)
root:layout(320)
t.assertSize(root, 320, 600, "safe-area inset fills its offered size")
t.assertEqual(refs.accessory.frame.origin.y, 0,
	"bottom accessory stays on the bottom AppKit edge")
t.assertSize(refs.content, 320, 540, "main content receives the space above the accessory")

local spaced, spacedRefs = xml.render([[
<SafeAreaInset edge="bottom" minimumBottomInset="24" keyboardBottomInset="12" horizontalInset="12" matchBottomHorizontalInset="true">
	<ScrollView id="content"><VStack><Label text="Scrollable content" /></VStack></ScrollView>
	<VStack id="accessory" height="60"><Label text="Persistent action" /></VStack>
</SafeAreaInset>]], {}, ns)
spaced.size = ns.Size(320, 600)
spaced:layout(320)
t.assertEqual(spaced.paddingBottom, 24, "minimum bottom clearance is available in the shared template API")
t.assertEqual(spacedRefs.accessory.superview.paddingHorizontal, 12,
	"composer horizontal clearance belongs to the accessory alone")
t.assertEqual(spacedRefs.content.frame.origin.x, 0, "scrolling content remains edge to edge")
t.assertSize(spacedRefs.content, 320, 516, "bottom inset reduces the scrolling region")

local overlay, overlap = xml.render([[
<SafeAreaInset edge="bottom" overlay="true" minimumBottomInset="24">
	<ScrollView id="content"><VStack height="1000"><Label text="Start" /></VStack></ScrollView>
	<VStack id="accessory" height="60" />
</SafeAreaInset>]], {}, ns)
overlay.size = ns.Size(320, 600)
overlay:layout(320)
t.assertSize(overlap.content, 320, 600, "overlay leaves the scroll view full height")
t.assertEqual(overlap.accessory.frame.origin.y, 24, "overlay keeps the accessory above its bottom clearance")
overlap.content:scrollTo("top", false)
t.assertEqual(overlap.content.contentView.bounds.origin.y, 400, "the first line is reachable")
overlap.content:scrollTo("bottom", false)
t.assertEqual(overlap.content.contentView.bounds.origin.y, -84, "the last line scrolls above the accessory")
overlap.accessory.fixedHeight = 90
overlay:layout(320)
overlap.content:scrollTo("bottom", false)
t.assertEqual(overlap.content.contentView.bounds.origin.y, -114, "resizing the accessory updates the scrolling clearance")
overlay.size = ns.Size(320, 0)
overlay:layout(320)
t.expect(overlap.content.size.height >= 0, "a zero-height overlay keeps a valid scrolling size")

local accepted = pcall(function()
	xml.render([[<SafeAreaInset edge="top"><VStack /><VStack /></SafeAreaInset>]], {}, ns)
end)
t.expect(not accepted, "unsupported inset edges fail clearly")

os.exit(t.summary() and 0 or 1)
