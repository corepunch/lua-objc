local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")

t.expect(src:find("function UIKit.Picker", 1, true) ~= nil, "UIKit Picker API exists")
t.expect(src:find("bridge._picker", 1, true) ~= nil, "UIKit Picker calls native bridge")
t.expect(constructors:find("UIPickerView", 1, true) ~= nil, "UIKit Picker uses UIPickerView")
t.expect(constructors:find("didSelectRow", 1, true) ~= nil, "UIKit Picker exposes selection callback")
t.expect(bridge:find('{"_picker", bridge_UIKitControls_picker}', 1, true) ~= nil,
	"UIKit Picker bridge is registered")

os.exit(t.summary() and 0 or 1)
