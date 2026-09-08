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

t.expect(appkit:find("function AppKit.DisclosureGroup", 1, true) ~= nil,
	"AppKit exposes stateful disclosure composition")
t.expect(uikit:find("function UIKit.DisclosureGroup", 1, true) ~= nil,
	"UIKit exposes stateful disclosure composition")
t.expect(appkit:find("content.hidden = not expanded", 1, true) ~= nil,
	"DisclosureGroup retains expanded state and hides native content")
t.expect(xml:find("DisclosureGroup =", 1, true) ~= nil,
	"XML registers DisclosureGroup")

os.exit(t.summary() and 0 or 1)
