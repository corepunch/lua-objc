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
t.expect(appkit:find("columnWidths[column]", 1, true) ~= nil
		and uikit:find("child.fixedWidth = columnWidths[column]", 1, true) ~= nil,
	"Grid shares measured column widths across rows")

os.exit(t.summary() and 0 or 1)
