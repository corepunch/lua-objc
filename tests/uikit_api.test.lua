local t = require("TestKit")

local src
do
	local f = assert(io.open("lua/embedded/UIKit.lua", "r"))
	src = f:read("*a")
	f:close()
end

t.expect(src:find("function UIKit.Window") ~= nil, "UIKit.Window exists")
t.expect(src:find("function UIKit.Toggle") ~= nil, "UIKit.Toggle exists")
t.expect(src:find("function UIKit.SystemImage") ~= nil, "UIKit.SystemImage exists")
t.expect(src:find("function UIKit.HostingController") ~= nil, "UIKit.HostingController exists")
t.expect(src:find("bridge%._installScene") ~= nil, "Window installs the scene")
t.expect(not src:find("bridge%._window%("), "480x360 _window path is gone")
t.expect(src:find("function UIKit.Switch") == nil, "Switch constructor is deleted")
t.expect(src:find("UIKit.Text = UIKit.Label") ~= nil, "Text aliases Label")

os.exit(t.summary() and 0 or 1)
