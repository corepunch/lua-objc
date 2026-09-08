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
local appkitFont = read("src/appkit/editor.m")
local uikitFont = read("src/uikit/platform.m")

t.expect(appkit:find("arg.italic", 1, true) ~= nil,
	"AppKit text accepts italic styling")
t.expect(appkit:find("v.alignment", 1, true) ~= nil,
	"AppKit text accepts semantic alignment")
t.expect(uikit:find("props.italic", 1, true) ~= nil,
	"UIKit text accepts italic styling")
t.expect(uikit:find("v.textAlignment", 1, true) ~= nil,
	"UIKit text accepts semantic alignment")
t.expect(xml:find('italic     = "bool"', 1, true) ~= nil,
	"XML exposes italic text")
t.expect(appkitFont:find("NSItalicFontMask", 1, true) ~= nil,
	"AppKit italic text uses the native font manager")
t.expect(uikitFont:find("UIFontDescriptorTraitItalic", 1, true) ~= nil,
	"UIKit italic text uses the native font descriptor")

os.exit(t.summary() and 0 or 1)
