local t = require("TestKit")

local appkit = assert(io.open("lua/embedded/AppKit.lua", "r")):read("*a")
local uikit = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(appkit:find("button.enabled = not props.disabled", 1, true) ~= nil,
	"AppKit Button forwards disabled state to native enabled")
t.expect(uikit:find("button.enabled = not props.disabled", 1, true) ~= nil,
	"UIKit Button forwards disabled state to native enabled")
t.expect(xml:find("disabled    = \"bool\"", 1, true) ~= nil,
	"XML Button exposes disabled state")

os.exit(t.summary() and 0 or 1)
