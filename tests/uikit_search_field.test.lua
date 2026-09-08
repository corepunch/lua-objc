local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local xml = assert(io.open("lua/ui/xml.lua", "r")):read("*a")

t.expect(src:find("function UIKit.SearchField", 1, true) ~= nil,
	"UIKit SearchField API exists")
t.expect(constructors:find("UISearchTextField", 1, true) ~= nil,
	"UIKit SearchField uses UISearchTextField")
t.expect(constructors:find("obj.placeholder", 1, true) ~= nil,
	"UIKit SearchField applies placeholder")
t.expect(bridge:find('{"_searchField", bridge_UIKitControls_searchField}', 1, true) ~= nil,
	"UIKit SearchField bridge is registered")
t.expect(xml:find("SearchField =", 1, true) ~= nil,
	"XML registers SearchField")

os.exit(t.summary() and 0 or 1)
