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

t.expect(appkit:find("function AppKit.Grid", 1, true) ~= nil,
	"AppKit provides grid rows using native stacks")
t.expect(uikit:find("function UIKit.Grid", 1, true) ~= nil,
	"UIKit provides grid rows using native stacks")
t.expect(xml:find("GridRow", 1, true) ~= nil,
	"XML provides explicit grid row structure")
t.expect(xml:find('constructor = "Grid"', 1, true) ~= nil,
	"XML registers Grid")

os.exit(t.summary() and 0 or 1)
