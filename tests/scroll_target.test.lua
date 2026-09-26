_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- SwiftUI containerRelativeFrame(.horizontal) inside a horizontal carousel.
local root, refs = xml.render([[
<VStack spacing="0">
	<ScrollView id="carousel" horizontal="true" vertical="false" scrollTargetBehavior="viewAligned">
		<HStack id="cards" spacing="12" paddingHorizontal="16" alignment="top">
			<VStack id="first" containerRelativeWidth="1" height="200" background="systemIndigo" />
			<VStack id="second" containerRelativeWidth="1" height="200" background="systemTeal" />
			<VStack id="half" containerRelativeWidth="0.5" height="120" background="systemPink" />
		</HStack>
	</ScrollView>
</VStack>]], {}, ns)

root.size = ns.Size(390, 600); root:layout(390)
t.assertEqual(refs.first.size.width, 390 - 32, "a full card fills the visible width less the content padding")
t.assertEqual(refs.second.size.width, 390 - 32, "every card resolves against the same viewport")
t.assertEqual(refs.half.size.width, math.floor((390 - 32) * 0.5), "fractions share the visible width")
t.expect(refs.carousel.size.height >= 200 and refs.carousel.size.height < 220, "the carousel is as tall as its tallest card (plus a legacy scroller) : " .. refs.carousel.size.height)
t.expect(refs.cards.size.width > 390, "cards extend past the viewport so the carousel scrolls")
t.assertEqual(refs.carousel.scrollTargetBehavior, "viewAligned", "the scroll target behavior is recorded")

root.size = ns.Size(820, 600); root:layout(820)
t.assertEqual(refs.first.size.width, 820 - 32, "resizing the window resizes container-relative cards")
root.size = ns.Size(390, 600); root:layout(390)
t.assertEqual(refs.first.size.width, 390 - 32, "restoring the width restores the cards")

-- A view outside any scroll view keeps its intrinsic width.
local plain = xml.render([[<VStack><Label id="x" text="Plain" containerRelativeWidth="1" /></VStack>]], {}, ns)
plain.size = ns.Size(300, 100); plain:layout(300)
t.expect(plain.subviews[1].size.width < 300, "containerRelativeWidth only applies inside a horizontal scroll view")

local uikit = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
t.expect(uikit:find("scrollViewWillEndDragging", 1, true) ~= nil,
	"UIKit snaps released drags to the content's children")
