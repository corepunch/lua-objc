local t = require("TestKit")

local function read(path)
	local f = assert(io.open(path, "r"))
	local body = f:read("*a")
	f:close()
	return body
end

local appkit = read("lua/embedded/AppKit.lua")
local uikit = read("lua/embedded/UIKit.lua")

t.expect(appkit:find("function AppKit.OutlineGroup", 1, true) ~= nil,
	"AppKit exposes recursive OutlineGroup")
t.expect(uikit:find("function UIKit.OutlineGroup", 1, true) ~= nil,
	"UIKit exposes recursive OutlineGroup")
t.expect(appkit:find("outlineItems(AppKit", 1, true) ~= nil
		and uikit:find("outlineItems(UIKit", 1, true) ~= nil,
	"OutlineGroup recursively composes nested native disclosure nodes")
t.expect(appkit:find("props.data or props.items", 1, true) ~= nil
		and uikit:find("props.data or props.items", 1, true) ~= nil,
	"OutlineGroup accepts tree data")

local ns = require("AppKit")
local view = ns.OutlineGroup {
		expanded = true,
		data = {{ title = "Root", children = {{ title = "Leaf" }} }},
}
t.expect(type(view) == "userdata", "OutlineGroup constructs a native AppKit view tree")

os.exit(t.summary() and 0 or 1)
