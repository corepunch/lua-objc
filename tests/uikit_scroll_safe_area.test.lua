_G.__headless = true
local t = require("TestKit")

-- UIKit is not loaded in the headless macOS runner, so these check the native
-- contract: a vertical scroll view under the iOS 26 tab bar and its bottom
-- accessory must be able to scroll its last row clear of both, as SwiftUI's
-- ScrollView does through the safe area.
local function read(path) return assert(io.open(path, "r")):read("*a") end
local layout = read("src/uikit/layout.m")
local constructors = read("src/uikit/constructors.m")
local lazy = read("src/uikit/lazy_collection.m")

local helper = layout:match("static CGFloat uikit_scroll_bottom_inset%(UIScrollView %*scroll%) {(.-)\n}")
t.expect(helper ~= nil, "UIKit has one shared scroll bottom-inset rule")
t.expect(helper and helper:find("scroll.safeAreaInsets.bottom", 1, true) ~= nil,
	"the inset follows the scroll view's live safe area (tab bar + accessory + home indicator)")
t.expect(helper and helper:find("ignoresSafeArea", 1, true) ~= nil
		and helper:find('@"bottom"', 1, true) ~= nil and helper:find('@"all"', 1, true) ~= nil,
	"ignoresSafeArea bottom/all opts a scroll view out")

local scrollImpl = constructors:match("@implementation LuaUIKitScrollView(.-)@end")
t.expect(scrollImpl ~= nil, "LuaUIKitScrollView implementation found")
t.expect(scrollImpl:find("self.alwaysBounceVertical ? uikit_scroll_bottom_inset(self) : 0", 1, true) ~= nil,
	"only vertical scroll views reserve the bottom inset; horizontal shelves do not")
t.expect(scrollImpl:find("topInset + minimumHeight + bottomInset", 1, true) ~= nil,
	"content size extends past the covered bottom so the last row can scroll above the bars")
t.expect(scrollImpl:find("content.height - topInset - bottomInset", 1, true) ~= nil,
	"filling content ends above the covered bottom instead of under the accessory")
t.expect(scrollImpl:find("self.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0)", 1, true) ~= nil,
	"the scroll indicator stops above the bars")
t.expect(scrollImpl:find("safeAreaInsetsDidChange", 1, true) ~= nil,
	"the scroll view re-lays out when the accessory appears, hides, or goes inline")

local lazyImpl = lazy:match("@implementation LuaLazyCollectionView(.-)@end")
t.expect(lazyImpl ~= nil, "LuaLazyCollectionView implementation found")
t.expect(lazyImpl:find("uikit_scroll_bottom_inset(self)", 1, true) ~= nil
		and lazyImpl:find("self.contentInset = UIEdgeInsetsMake(0, 0, bottomInset, 0)", 1, true) ~= nil,
	"lazy stacks and grids share the same bottom content inset")
t.expect(lazyImpl:find("safeAreaInsetsDidChange", 1, true) ~= nil,
	"lazy collections follow safe-area changes")

os.exit(t.summary() and 0 or 1)
