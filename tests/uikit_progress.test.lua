local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(src:find("function UIKit.ProgressView", 1, true) ~= nil,
	"UIKit ProgressView API exists")
t.expect(src:find("props.value ~= nil", 1, true) ~= nil,
	"UIKit ProgressView distinguishes determinate progress")
t.expect(constructors:find("UIProgressView", 1, true) ~= nil
		and constructors:find("obj.progress", 1, true) ~= nil,
	"UIKit determinate progress uses UIProgressView")
t.expect(bridge:find('{"_progressView", bridge_UIKitControls_progressView}', 1, true) ~= nil,
	"UIKit ProgressView bridge is registered")
t.expect(xml:find("ProgressView =", 1, true) ~= nil,
	"XML registers ProgressView")

os.exit(t.summary() and 0 or 1)
