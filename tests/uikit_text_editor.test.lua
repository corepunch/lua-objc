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
t.expect(constructors:find("@interface LuaTextView : UITextView", 1, true)
	and constructors:find("@interface LuaTextField : UITextField", 1, true)
	and constructors:find("set_verbatim_input(self, value)", 1, true),
	"native text controls expose semantic verbatim editing through KVC")
t.expect(constructors:find("UITextSmartQuotesTypeNo", 1, true)
	and constructors:find("UITextSmartDashesTypeNo", 1, true)
	and constructors:find("UITextAutocorrectionTypeNo", 1, true),
	"verbatim editing configures forwarded UIKit traits through their native API")

os.exit(t.summary() and 0 or 1)
