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
t.expect(src:find("v.numberOfLines = props.lineLimit", 1, true) ~= nil,
	"UIKit labels honor explicit line limits")

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

os.exit(t.summary() and 0 or 1)
