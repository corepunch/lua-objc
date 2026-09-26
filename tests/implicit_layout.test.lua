_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

local root, refs = xml.render([[
<VStack alignment="leading" spacing="0">
	<Label id="short" text="Short" />
	<Label id="long" text="This paragraph must wrap at the available width without requesting an infinite frame." lines="0" />
	<HStack id="composer" spacing="8">
		<TextField id="input" value="Keep me" />
		<Button id="send" title="Send" />
	</HStack>
</VStack>]], {}, ns)
root.size = ns.Size(240, 300); root:layout(240)
t.expect(refs.short.size.width < 100, "short text retains intrinsic width")
t.assertEqual(refs.short.frame.origin.x, 0, "stack alignment places natural text at leading edge")
t.expect(refs.long.size.width <= 240 and refs.long.size.height > refs.short.size.height,
	"text wraps against the parent proposal without maxWidth")
t.assertEqual(refs.composer.size.width, 240, "stack inherits text field flexibility")
t.assertEqual(refs.input.size.width + refs.send.size.width + 8, 240, "text field takes remaining width by default")
t.expect(refs.send.frame.size.width + 1 >= refs.send.fittingSize.width, "button keeps the width of its title")
root.size = ns.Size(480, 300); root:layout(480)
t.assertEqual(refs.input.text, "Keep me", "implicit resize preserves editing state")
t.assertEqual(refs.input.size.width + refs.send.size.width + 8, 480, "implicit text field expands after resize")

local hero, h = xml.render([[
<VStack spacing="0">
	<Button id="button" style="plain" accessibilityLabel="Open adventure" action="open">
		<ZStack id="hero" height="280" alignment="bottomLeading">
			<Image id="image" path="apps/adventure-arena/assets/planetfall.jpg" resizable="true" contentMode="fill" />
			<LinearGradient id="gradient" />
			<VStack id="caption" alignment="leading" padding="12"><Label text="Caption" /></VStack>
		</ZStack>
	</Button>
</VStack>]], { actions = { open = function() end } }, ns)
hero.size = ns.Size(400, 400); hero:layout(400)
t.assertSize(h.button, 400, 280, "native button measures its label content")
t.assertSize(h.image, 400, 280, "resizable image accepts the hero proposal")
t.assertSize(h.gradient, 400, 280, "gradient fills its proposal without sizing attributes")
t.assertEqual(h.caption.frame.origin.x, 0, "bottomLeading positions caption naturally")
t.assertEqual(h.caption.frame.origin.y, 0, "bottomLeading removes the need for a spacer")
t.expect(h.caption.size.width < 400 and h.caption.size.height < 100, "caption retains natural dimensions")
t.expect(h.button.className:find("Button") ~= nil, "content label is hosted by a native button")
t.assertEqual(h.button.accessibilityLabel, "Open adventure", "content button preserves accessibility label")
t.expect(ns._hitTestTarget(h.button, h.button, 20, h.button.frame.origin.y + 20),
	"label content does not intercept native button hit testing")
hero.size = ns.Size(200, 400); hero:layout(200)
t.assertSize(h.button, 200, 280, "button follows its flexible content after resize")
t.assertSize(h.gradient, 200, 280, "implicit gradient follows resize")
h.button.enabled = false
t.expect(not h.button.enabled, "content button retains native disabled state")

local list, l = xml.render([[
<VStack spacing="0">
	<ScrollView id="strip" horizontal="true" vertical="false">
		<HStack id="cards" spacing="12">
			<VStack width="130" height="176" />
			<VStack width="130" height="200" />
			<VStack width="130" height="176" />
		</HStack>
	</ScrollView>
	<Label id="after" text="Below the strip" />
</VStack>]], {}, ns)
list.size = ns.Size(240, 400); list:layout(240)
t.assertEqual(l.cards.size.width, 414, "scroll content measures its width without item-count arithmetic")
t.expect(l.strip.contentSize.height >= 200, "horizontal scroll view derives height from tallest child")
t.expect(l.strip.size.height < 240, "horizontal strip does not greedily consume vertical space")
t.expect(l.after.frame.origin.y + l.after.size.height <= l.strip.frame.origin.y, "following content remains below the natural scroll height")
list.size = ns.Size(600, 400); list:layout(600)
t.expect(l.cards.size.width >= 600, "short scroll content fills its viewport after widening")
os.exit(t.summary() and 0 or 1)
