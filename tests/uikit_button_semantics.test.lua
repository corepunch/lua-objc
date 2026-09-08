local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local native = assert(io.open("src/uikit/constructors.m", "r")):read("*a")

t.expect(src:find("props.systemImage", 1, true) ~= nil
		and src:find("props.role", 1, true) ~= nil,
	"UIKit Button forwards symbol and role")
t.expect(native:find("configuration.image", 1, true) ~= nil
		and native:find("systemRedColor", 1, true) ~= nil,
	"UIKit Button uses native image and destructive styling")
t.expect(native:find("borderedProminentButtonConfiguration", 1, true) ~= nil,
	"UIKit Button uses current bordered prominent configuration")

os.exit(t.summary() and 0 or 1)
