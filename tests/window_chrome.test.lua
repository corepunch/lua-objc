_G.__headless = true
local ns = require("AppKit")
local xml = require("ui.xml")
local t = require("TestKit")

local function height(view) return view.frame.size.height end

-- SwiftUI safe area on a full-size-content window: content sits below the
-- title bar and toolbar, and `ignoresSafeArea` extends a background under
-- them.
local closed = 0
local config, refs = xml.render([[
<Window title="Chrome" width="600" height="400" transparentTitlebar="true" hideTitle="false" level="floating" aspectRatio="1.5" onClose="closed">
	<Toolbar>
		<ToolbarItem id="go" label="Go" icon="play.fill" action="closed" />
	</Toolbar>
	<ZStack id="root" maxWidth="infinity" maxHeight="infinity">
		<VStack id="backdrop" background="systemBlue" maxWidth="infinity" maxHeight="infinity" ignoresSafeArea="all" />
		<VStack id="top" height="40" maxWidth="infinity" ignoresSafeArea="top" />
		<VStack id="content" maxWidth="infinity" maxHeight="infinity" />
	</ZStack>
</Window>]], {actions = {closed = function() closed = closed + 1 end}}, ns)
local window = ns.Window(config)
local safe = window.contentLayoutRect.size.height
t.expect(safe < 400, "a toolbar over full-size content leaves a smaller safe area")
t.assertEqual(height(refs.root), safe, "the window's content is laid out in the safe area")
t.assertEqual(height(refs.content), safe, "so its children stay clear of the toolbar")
t.assertEqual(height(refs.backdrop), 400, "ignoresSafeArea extends a view under the title bar and toolbar")
t.assertEqual(refs.backdrop.frame.origin.y, 0, "down to the window's bottom edge")
t.assertEqual(height(refs.top), 40, "an edge the view does not touch stays where layout put it")
t.assertEqual(refs.backdrop.ignoresSafeArea, "all", "the edges are readable")

-- Mini-player chrome: floating level, fixed aspect ratio, close callback.
t.assertEqual(window.windowLevel, "floating", "level=floating raises the window")
t.expect(window.level >= 3, "to AppKit's floating window level")
t.expect(math.abs(window.aspectRatio - 1.5) < 1e-6, "aspectRatio fixes the content's proportions")
window.windowLevel = "normal"
t.assertEqual(window.windowLevel, "normal", "the level can return to normal")
t.assertThrows(function() window.windowLevel = "sky" end, "unknown levels are rejected")
window.aspectRatio = 0
t.assertEqual(window.aspectRatio, 0, "an aspect ratio of 0 resizes freely")
window:hide()
t.expect(not window.visible, "hide orders a window out without closing it")
window:close()
t.assertEqual(closed, 1, "onClose runs when the window closes")

-- An ordinary window keeps its whole content view.
local plainConfig, plainRefs = xml.render([[
<Window title="Plain" width="300" height="200">
	<VStack id="body" maxWidth="infinity" maxHeight="infinity" />
</Window>]], {}, ns)
local plain = ns.Window(plainConfig)
t.assertEqual(height(plainRefs.body), 200, "a window with a solid title bar has no inset content")
plain:close()

os.exit(t.summary() and 0 or 1)
