local t = require("TestKit")

local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local appkitNative = assert(io.open("src/appkit/constructors.m", "r")):read("*a")
local uikitNative = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

for _, name in ipairs({ "DatePicker", "ColorPicker" }) do
	t.expect(appkit:find("function AppKit." .. name, 1, true) ~= nil,
		"AppKit exposes " .. name)
	t.expect(uikit:find("function UIKit." .. name, 1, true) ~= nil,
		"UIKit exposes " .. name)
	t.expect(xml:find(name .. " =", 1, true) ~= nil,
		"XML registers " .. name)
end
t.expect(appkitNative:find("NSDatePicker", 1, true) ~= nil
		and appkitNative:find("NSColorWell", 1, true) ~= nil,
	"AppKit uses native date and color wells")
t.expect(uikitNative:find("UIDatePicker", 1, true) ~= nil
		and uikitNative:find("UIColorWell", 1, true) ~= nil,
	"UIKit uses native date and color wells")

-- UIKit is not loaded in the headless macOS runner, so these check the value
-- contract: onChange receives the new value, as on AppKit. The shared
-- LuaButtonTarget calls Lua with no arguments, so a control wired to it must
-- have a wrapper that reads its own value; a Picker in any style reports the
-- zero-based index it selected (Adventure Arena's font picker did nothing).
local picker = uikitNative:match("static int bridge_UIKitControls_picker%(lua_State %*L%) {(.-)\n}\n")
t.expect(picker ~= nil, "UIKit picker constructor found")
local segmented = picker and picker:match('strcmp%(style, "segmented"%) == 0%) {(.-)return 1;')
t.expect(segmented and segmented:find("LuaButtonTarget", 1, true) == nil,
	"a segmented picker does not use the argument-less shared target")
t.expect(segmented and segmented:find("lua_pushinteger(callL, weakSegmented.selectedSegmentIndex)", 1, true) ~= nil,
	"a segmented picker reports its selected index")
t.expect(picker and picker:find("lua_pushinteger(callL, index)", 1, true) ~= nil,
	"a menu picker reports the chosen index")
local wheel = uikitNative:match("didSelectRow:%(NSInteger%)row(.-)\n}")
t.expect(wheel and wheel:find("lua_pushinteger(L, row)", 1, true) ~= nil
		and wheel:find("push_objc", 1, true) == nil,
	"a wheel picker reports the selected row, not the view")
local slider = uikit:match("function UIKit%.Slider%(props%)(.-)\nend")
t.expect(slider and slider:find("onChange = function() props.onChange(slider.value) end", 1, true) ~= nil,
	"UIKit Slider onChange receives the slider's value")
local stepper = uikit:match("function UIKit%.Stepper%(props%)(.-)\nend")
t.expect(stepper and stepper:find("onChange = function() props.onChange(stepper.value) end", 1, true) ~= nil,
	"UIKit Stepper onChange receives the stepper's value")

os.exit(t.summary() and 0 or 1)
