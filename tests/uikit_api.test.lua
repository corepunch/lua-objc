local t = require("TestKit")

local src
do
	local f = assert(io.open("lua/embedded/UIKit.lua", "r"))
	src = f:read("*a")
	f:close()
end

t.expect(src:find("function UIKit.Window") ~= nil, "UIKit.Window exists")
t.expect(src:find("function UIKit.Toggle") ~= nil, "UIKit.Toggle exists")
t.expect(src:find("UIKit.Label(label)", 1, true) ~= nil
	and src:find("UIKit.Spacer()", 1, true) ~= nil
	and src:find("labelView.numberOfLines = 1", 1, true) ~= nil
	and src:find("labelView.lineBreakMode = 4", 1, true) ~= nil
	and src:find("control.enabled = not props.disabled", 1, true) ~= nil,
	"UIKit Toggle pairs its native switch with a one-line visible label and preserves disabled state")
t.expect(src:find("function UIKit.SystemImage") ~= nil, "UIKit.SystemImage exists")
t.expect(src:find('arg.color or "primary"', 1, true) ~= nil,
	"UIKit system images inherit the primary foreground color by default")
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
t.expect(src:find('"ignoresSafeArea"', 1, true) ~= nil,
	"UIKit exposes safe-area edge control")
t.expect(src:find('"clipsToBounds"', 1, true) ~= nil,
	"UIKit exposes square clipping independently of corner radius")
t.expect(src:find('"background"', 1, true) ~= nil
		and src:find("view.backgroundColor = bridge._systemColor(props[key])", 1, true) ~= nil,
	"UIKit applies semantic background colors to every declarative view")
t.expect(src:find("button.titleLabel.lineBreakMode", 1, true) ~= nil,
	"UIKit buttons support explicit tail truncation")
t.expect(src:find("function UIKit.Slider", 1, true) ~= nil
		and src:find("function UIKit.Stepper", 1, true) ~= nil,
	"UIKit exposes native slider and stepper controls")

local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
t.expect(bridge:find('"_slider"', 1, true) ~= nil
		and bridge:find('"_stepper"', 1, true) ~= nil,
	"UIKit registers slider and stepper bridge constructors")
t.expect(constructors:find("UISlider", 1, true) ~= nil
		and constructors:find("UIStepper", 1, true) ~= nil,
	"UIKit slider and stepper use native controls")
t.expect(src:find("secureTextEntry", 1, true) ~= nil,
	"UIKit text fields expose native secure entry")

local layout = assert(io.open("src/uikit/layout.m", "r")):read("*a")
local views = assert(io.open("src/uikit/views.m", "r")):read("*a")
t.expect(layout:find("kImageLayoutSizeKey", 1, true) ~= nil,
	"UIKit layout preserves image display size during size-to-fit")
t.expect(views:find("objc_setAssociatedObject(iv, &kImageLayoutSizeKey", 1, true) ~= nil,
	"UIKit images publish their proportional layout size")
t.expect(views:find("kImageMaxWidth", 1, true) ~= nil,
	"UIKit data-backed images use the same display-size limit")
-- Fixed dimensions and empty/hidden/nested sizing are exercised by the
-- shared native contracts, including in the live UIKit batch host.
t.expect(layout:find("view_padding_top", 1, true) ~= nil
	and layout:find("view_padding_bottom", 1, true) ~= nil,
	"UIKit stack measurement honors asymmetric vertical padding")
t.expect(layout:find("view_fixed_width(sv)", 1, true) ~= nil,
	"UIKit overlay stacks preserve fixed child geometry")

local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
t.expect(constructors:find("contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever", 1, true) ~= nil,
	"UIKit scroll views do not duplicate host safe-area insets")
t.expect(constructors:find("scroll.contentInset = UIEdgeInsetsZero", 1, true) ~= nil,
	"UIKit scroll views start content at their declared edge")
t.expect(constructors:find("self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever", 1, true) ~= nil,
	"UIKit scroll views retain edge placement after layout")
t.expect(constructors:find("CGFloat topInset = view_padding_top(self)", 1, true) ~= nil
	and constructors:find("MAX(viewport.height, topInset + minimumHeight)", 1, true) ~= nil
	and constructors:find("CGRectMake(0, topInset, content.width", 1, true) ~= nil,
	"UIKit root scroll views place content below the host safe area")
-- Relayout must preserve user scrolling; offsets are owned by UIScrollView.
t.expect(constructors:find("gradient.locations", 1, true) ~= nil,
	"UIKit gradients preserve SwiftUI-like stop locations")
t.expect(constructors:find("view.backgroundColor = UIColor.clearColor", 1, true) ~= nil,
	"UIKit page controls render dots without a capsule")
local pageControlImplementation = constructors:match("(static int bridge_UIKitControls_pageControl.-)\n@interface")
t.expect(pageControlImplementation ~= nil
	and pageControlImplementation:find("cornerRadius", 1, true) == nil,
	"UIKit page controls do not add custom capsule corners")

local hosting = assert(io.open("src/uikit/hosting.m", "r")):read("*a")
local presentation = assert(io.open("src/uikit/presentation.m", "r")):read("*a")
local preview = assert(io.open("src/uikit/preview.m", "r")):read("*a")
local runtime = assert(io.open("src/uikit/runtime.m", "r")):read("*a")
local structs = assert(io.open("src/uikit/structs.m", "r")):read("*a")
t.expect(structs:find("lua_objc.struct.CGSize", 1, true) ~= nil,
	"UIKit defines CGSize userdata metatable")
t.expect(structs:find("lua_objc.struct.CGPoint", 1, true) ~= nil,
	"UIKit defines CGPoint userdata metatable")
t.expect(structs:find("lua_objc.struct.CGRect", 1, true) ~= nil,
	"UIKit defines CGRect userdata metatable")
t.expect(structs:find("bridge_CGSize", 1, true) ~= nil,
	"UIKit exports CGSize constructor")
t.expect(structs:find("bridge_CGPoint", 1, true) ~= nil,
	"UIKit exports CGPoint constructor")
t.expect(structs:find("bridge_CGRect", 1, true) ~= nil,
	"UIKit exports CGRect constructor")
t.expect(runtime:find("push_kvc_value", 1, true) ~= nil,
	"UIKit runtime converts NSValue structs on KVC read")
t.expect(runtime:find("lua_to_kvc_value", 1, true) ~= nil,
	"UIKit runtime converts struct userdata on KVC write")
t.expect(runtime:find("GEN_STRUCT_HELPERS", 1, true) ~= nil,
	"UIKit runtime includes struct helpers")
t.expect(bridge:find('"Size"', 1, true) ~= nil
		and bridge:find('"Point"', 1, true) ~= nil
		and bridge:find('"Rect"', 1, true) ~= nil,
	"UIKit registers Size/Point/Rect in bridge_lib")
t.expect(bridge:find("GEN_STRUCT_REGISTER", 1, true) ~= nil,
	"UIKit registers struct metatables at module load")
t.expect(hosting:find("keyboardLayoutGuide.topAnchor", 1, true) ~= nil,
	"hosting bounds account for the software keyboard")
t.expect(hosting:find("keyboardLayoutGuide.usesBottomSafeArea = NO", 1, true) ~= nil
	and hosting:find("MAX(self.view.safeAreaInsets.bottom, view.minimumBottomInset)", 1, true) ~= nil
	and hosting:find("keyboardVisible ? view.keyboardBottomInset", 1, true) ~= nil
	and hosting:find("keyboardVisible ? view.horizontalInset : bottomInset", 1, true) ~= nil,
	"keyboard guide gives the composer its own bottom and horizontal clearance")
t.expect(src:find("accessory.safeAreaInsetBottom = true", 1, true) ~= nil
	and src:find("accessory.matchBottomHorizontalInset = props.matchBottomHorizontalInset == true", 1, true) ~= nil,
	"only the accessory receives dynamic safe-area clearance")
t.expect(hosting:find("luaRoot.topAnchor constraintEqualToAnchor:self.view.topAnchor", 1, true) ~= nil
	and hosting:find("luaRoot.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor", 1, true) ~= nil
	and hosting:find("luaRoot.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor", 1, true) ~= nil,
	"hosting root fills the window behind system chrome")
t.expect(hosting:find("viewSafeAreaInsetsDidChange", 1, true) ~= nil
	and hosting:find("kHostSafeAreaTopKey", 1, true) ~= nil,
	"hosting converts the status-bar inset into top layout padding")
t.expect(hosting:find("CGRectGetMinY(tabFrame) >= CGRectGetMaxY(self.luaRoot.frame)", 1, true) ~= nil
	and hosting:find("bottomInset = 0", 1, true) ~= nil,
	"bottom inset does not count an external tab bar twice")
local gestures = assert(io.open("src/uikit/views.m", "r")):read("*a")
local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
t.expect(constructors:find("@interface LuaLayoutView : UIView", 1, true) ~= nil
	and constructors:find("target == self && self.gestureRecognizers.count == 0 ? nil : target", 1, true) ~= nil
	and select(2, constructors:gsub("%[%[LuaLayoutView alloc%] initWithFrame:CGRectZero%]", "")) == 4,
	"empty stack padding passes taps through overlays while stack gestures remain active")
t.expect(gestures:find('strcmp(name, "systemIndigo") == 0', 1, true) ~= nil,
	"UIKit resolves the AI category's semantic color")
t.expect(gestures:find("UIScreenEdgePanGestureRecognizer", 1, true) ~= nil
	and gestures:find("kEdgeSwipeBackDistance", 1, true) ~= nil,
	"session back navigation uses a native left-edge recognizer")
t.expect(presentation:find("if (presenter.presentingViewController)", 1, true) ~= nil,
	"dismiss targets the presented controller")
t.expect(preview:find("addChildViewController", 1, true) ~= nil
	and preview:find("removeFromParentViewController", 1, true) ~= nil,
	"preview replacement balances native controller containment")
t.expect(preview:find("UIUserInterfaceIdiomPhone", 1, true) ~= nil,
	"embedded preview uses phone traits")
local loader = assert(io.open("ios/LuaRuntime/LRTResourceLoader.m", "r")):read("*a")
t.expect(loader:find("self.localRoot.stringByStandardizingPath", 1, true) ~= nil,
	"device bundle root is normalized before the resource containment check")

os.exit(t.summary() and 0 or 1)
