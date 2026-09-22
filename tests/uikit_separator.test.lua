_G.__headless = true
local t = require("TestKit")

local orientation
local bridge = {
	sidebarIconSize = 20,
	sidebarIconSlotWidth = 32,
	sidebarRowPadding = 8,
	sidebarExpandedPadding = 12,
	sidebarCollapsedPadding = 8,
	sidebarExpandedWidth = 208,
	sidebarCompactWidth = 184,
	sidebarCollapsedWidth = 64,
	_separator = function(value)
		orientation = value
		return {}
	end,
}
package.loaded.UIKitNative = bridge
local UIKit = assert(loadfile("lua/embedded/UIKit.lua"))()

UIKit.Separator({ orientation = "vertical" })
t.assertEqual(orientation, "vertical", "UIKit forwards vertical divider orientation")
UIKit.Separator({})
t.assertEqual(orientation, "horizontal", "UIKit defaults separators to horizontal")
os.exit(t.summary() and 0 or 1)
