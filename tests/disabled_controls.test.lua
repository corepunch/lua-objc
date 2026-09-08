local t = require("TestKit")

local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

for _, source in ipairs({ appkit, uikit }) do
	t.expect(source:find("props.disabled", 1, true) ~= nil,
		"native input wrappers inspect disabled state")
end
t.expect(xml:find("disabled = \"bool\"", 1, true) ~= nil,
	"XML input controls expose disabled state")

os.exit(t.summary() and 0 or 1)
