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
local runtime = read("src/appkit/runtime.m")

t.expect(appkit:find('"background"', 1, true) ~= nil,
	"AppKit exposes semantic background colors")
t.expect(appkit:find('"cornerRadius"', 1, true) ~= nil,
	"AppKit exposes native corner radii")
t.expect(uikit:find('"background"', 1, true) ~= nil,
	"UIKit exposes semantic background colors")
t.expect(xml:find('"background"', 1, true) ~= nil,
	"XML forwards background colors through the shared layout contract")
t.expect(runtime:find("self.layer.backgroundColor = value.CGColor", 1, true) ~= nil,
	"AppKit backgrounds are rendered by the native backing layer")
t.expect(runtime:find("self.layer.masksToBounds = value", 1, true) ~= nil,
	"AppKit clipping is native layer clipping")

os.exit(t.summary() and 0 or 1)
