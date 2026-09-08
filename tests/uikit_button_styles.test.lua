local t = require("TestKit")

local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")

t.expect(constructors:find("UIButtonConfiguration", 1, true) ~= nil,
	"UIKit buttons use native configuration styles")
t.expect(constructors:find("borderedButtonConfiguration", 1, true) ~= nil,
	"UIKit exposes bordered button style")
t.expect(constructors:find("borderedProminentButtonConfiguration", 1, true) ~= nil,
	"UIKit exposes bordered prominent button style")
t.expect(constructors:find('strcmp(style, "link")', 1, true) ~= nil,
	"UIKit exposes native link button style")
t.expect(src:find("style = type(props) == \"table\" and props.style", 1, true) ~= nil,
	"UIKit Lua button forwards style")

os.exit(t.summary() and 0 or 1)
