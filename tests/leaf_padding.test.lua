_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- SwiftUI's .padding applies to any view, including leaves that draw edge
-- to edge in their frames. The renderer wraps a padded leaf in a stack.
local root, refs = xml.render([[
<VStack id="root" spacing="0" alignment="leading">
	<Label id="heading" text="Continue Reading" size="22" paddingHorizontal="16" paddingTop="10" />
	<Label id="plain" text="Unpadded" />
	<Label id="hiddenStatus" text="Listening…" paddingHorizontal="20" hidden="true" />
	<Label id="wide" text="Fills" paddingHorizontal="12" maxWidth="infinity" />
	<HStack id="stack" paddingHorizontal="8"><Label text="In a stack" /></HStack>
</VStack>]], {}, ns)
root.size = ns.Size(300, 400); root:layout(300)

t.assertEqual(refs.heading.text, "Continue Reading", "the id still names the leaf, not its wrapper")
t.assertEqual(refs.heading.frame.origin.x, 16, "leading padding insets a leaf")
t.expect(refs.heading.superview ~= root and refs.heading.superview.superview == root,
	"a padded leaf is hosted by one wrapping stack")
t.assertEqual(refs.plain.superview, root, "an unpadded leaf is not wrapped")
t.assertEqual(refs.stack.superview, root, "a stack pads its own children and is not wrapped")
t.assertEqual(refs.stack.subviews[1].frame.origin.x, 8, "stack padding is unchanged")
t.expect(refs.hiddenStatus.superview.frame.size.height == 0,
	"a hidden padded leaf takes no height, so a controller can show it later")
refs.hiddenStatus.hidden = false
root:layout(300)
t.expect(refs.hiddenStatus.superview.frame.size.height > 0, "showing the leaf reveals it inside its padding")
t.assertEqual(refs.wide.superview.frame.size.width, 300, "maxWidth expands the padded wrapper")
t.assertEqual(refs.wide.frame.size.width, 300 - 24, "the leaf fills the wrapper inside its padding")
