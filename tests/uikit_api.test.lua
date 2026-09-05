local t = require("TestKit")

local src
do
	local f = assert(io.open("lua/embedded/UIKit.lua", "r"))
	src = f:read("*a")
	f:close()
end

t.expect(src:find("function UIKit.Window") ~= nil, "UIKit.Window exists")
t.expect(src:find("function UIKit.Toggle") ~= nil, "UIKit.Toggle exists")
t.expect(src:find("function UIKit.SystemImage") ~= nil, "UIKit.SystemImage exists")
t.expect(src:find("function UIKit.HostingController") ~= nil, "UIKit.HostingController exists")
t.expect(src:find("bridge%._installScene") ~= nil, "Window installs the scene")
t.expect(not src:find("bridge%._window%("), "480x360 _window path is gone")
t.expect(src:find("function UIKit.Switch") == nil, "Switch constructor is deleted")
t.expect(src:find("UIKit.Text = UIKit.Label") ~= nil, "Text aliases Label")
t.expect(src:find("v:sizeToFit%(%)[%s%S]-end") ~= nil,
	"UIKit labels resize after applying a custom font")
t.expect(src:find("local lines = props.lineLimit or props.lines", 1, true) ~= nil,
	"UIKit labels honor explicit line limits")
t.expect(src:find("props.vertical ~= false", 1, true) ~= nil,
	"UIKit ScrollView defaults to vertical scrolling like SwiftUI")
t.expect(src:find('"paddingHorizontal"', 1, true) ~= nil
		and src:find('"fillHeight"', 1, true) ~= nil,
	"UIKit exposes the shared layout property contract")
t.expect(src:find("function UIKit.ZStack", 1, true) ~= nil,
	"UIKit exposes a native overlay stack")
t.expect(src:find("function UIKit.NavigationStack", 1, true) ~= nil,
	"UIKit exposes a native navigation stack")
t.expect(src:find("props.middleLocation", 1, true) ~= nil,
	"UIKit gradients expose an intermediate fade stop")
t.expect(src:find('"paddingTop"', 1, true) ~= nil
		and src:find('"paddingBottom"', 1, true) ~= nil,
	"UIKit exposes edge-specific padding")

local layout = assert(io.open("src/uikit/layout.m", "r")):read("*a")
local views = assert(io.open("src/uikit/views.m", "r")):read("*a")
t.expect(layout:find("kImageLayoutSizeKey", 1, true) ~= nil,
	"UIKit layout preserves image display size during size-to-fit")
t.expect(views:find("objc_setAssociatedObject(iv, &kImageLayoutSizeKey", 1, true) ~= nil,
	"UIKit images publish their proportional layout size")
t.expect(views:find("kImageMaxWidth", 1, true) ~= nil,
	"UIKit data-backed images use the same display-size limit")
t.expect(layout:find("CGFloat fixedHeight = view_fixed_height(view);", 1, true) ~= nil,
	"UIKit stack measurement honors fixed child heights")
t.expect(layout:find("view_padding_top", 1, true) ~= nil
		and layout:find("view_padding_bottom", 1, true) ~= nil,
	"UIKit stack measurement honors asymmetric vertical padding")

local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
t.expect(constructors:find("gradient.locations", 1, true) ~= nil,
	"UIKit gradients preserve SwiftUI-like stop locations")
t.expect(constructors:find("layer.borderWidth = 1", 1, true) ~= nil,
	"UIKit page controls retain the outlined capsule")

os.exit(t.summary() and 0 or 1)
