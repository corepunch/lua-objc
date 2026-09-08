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

for _, name in ipairs({ "Form", "LabeledContent", "ControlGroup" }) do
	t.expect(appkit:find("function AppKit." .. name, 1, true) ~= nil,
		"AppKit exposes " .. name .. " composition")
	t.expect(uikit:find("function UIKit." .. name, 1, true) ~= nil,
		"UIKit exposes " .. name .. " composition")
	t.expect(xml:find(name .. " =", 1, true) ~= nil,
		"XML registers " .. name)
end

os.exit(t.summary() and 0 or 1)
