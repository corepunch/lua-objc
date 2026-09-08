local t = require("TestKit")

local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

for _, name in ipairs({ "ContentUnavailable" }) do
	t.expect(appkit:find("function AppKit." .. name, 1, true) ~= nil,
		"AppKit exposes native composition " .. name)
	t.expect(uikit:find("function UIKit." .. name, 1, true) ~= nil,
		"UIKit exposes native composition " .. name)
	t.expect(xml:find(name .. " =", 1, true) ~= nil,
		"XML registers " .. name)
end
t.expect(uikit:find("UIKit.SystemImage", 1, true) ~= nil
		and uikit:find("UIKit.Title", 1, true) ~= nil
		and uikit:find("UIKit.Label", 1, true) ~= nil,
	"UIKit ContentUnavailable uses native image and text nodes")

os.exit(t.summary() and 0 or 1)
