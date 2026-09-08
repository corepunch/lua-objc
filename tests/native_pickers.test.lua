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

os.exit(t.summary() and 0 or 1)
