local t = require("TestKit")

local function read(path)
	local f = assert(io.open(path, "r"))
	local body = f:read("*a")
	f:close()
	return body
end

local appkit = read("lua/embedded/AppKit.lua")
local uikit = read("lua/embedded/UIKit.lua")
local xml = read("lua/ui/xml.lua")

t.expect(appkit:find("function AppKit.Section", 1, true) ~= nil,
	"AppKit exposes nested Section composition")
t.expect(appkit:find("function AppKit.GroupBox", 1, true) ~= nil,
	"AppKit exposes native-surface GroupBox composition")
t.expect(uikit:find("function UIKit.Section", 1, true) ~= nil,
	"UIKit exposes nested Section composition")
t.expect(uikit:find("function UIKit.GroupBox", 1, true) ~= nil,
	"UIKit exposes native-surface GroupBox composition")
t.expect(xml:find("Section =", 1, true) ~= nil
		and xml:find("GroupBox =", 1, true) ~= nil,
	"XML registers Section and GroupBox")

os.exit(t.summary() and 0 or 1)
