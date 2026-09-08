local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local constructors = assert(io.open("src/uikit/constructors.m", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")

t.expect(src:find("function UIKit.TextEditor", 1, true) ~= nil,
	"UIKit TextEditor API exists")
t.expect(src:find("bridge._textEditor", 1, true) ~= nil,
	"UIKit TextEditor calls native bridge")
t.expect(constructors:find("UITextView", 1, true) ~= nil,
	"UIKit TextEditor uses UITextView")
t.expect(constructors:find("obj.editable", 1, true) ~= nil
		and constructors:find("obj.selectable", 1, true) ~= nil,
	"UIKit TextEditor applies editing and selection state")
t.expect(constructors:find("backgroundColor = UIColor.clearColor", 1, true) ~= nil,
	"UIKit TextEditor applies background visibility")
t.expect(bridge:find('{"_textEditor", bridge_UIKitControls_textEditor}', 1, true) ~= nil,
	"UIKit TextEditor bridge is registered")

os.exit(t.summary() and 0 or 1)
