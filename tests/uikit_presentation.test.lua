local t = require("TestKit")

local src = assert(io.open("lua/embedded/UIKit.lua", "r")):read("*a")
local bridge = assert(io.open("src/uikit/bridge.m", "r")):read("*a")
local native = assert(io.open("src/uikit/presentation.m", "r")):read("*a")
local navigation = assert(io.open("src/uikit/navigation.m", "r")):read("*a")
local hosting = assert(io.open("src/uikit/hosting.m", "r")):read("*a")

t.expect(src:find("function UIKit.presentSheet", 1, true) ~= nil,
	"UIKit exposes native sheet presentation")
t.expect(src:find("function UIKit.dismiss", 1, true) ~= nil,
	"UIKit exposes native dismissal")
t.expect(native:find("UISheetPresentationController", 1, true) ~= nil
		and native:find("UIModalPresentationPageSheet", 1, true) ~= nil,
	"UIKit sheets use native page-sheet presentation")
t.expect(native:find("UIModalPresentationFormSheet",1,true) and native:find('"presentationStyle"',1,true),
	"UIKit also exposes native form-sheet popup presentation")
t.expect(native:find("mediumDetent", 1, true) ~= nil
		and native:find("largeDetent", 1, true) ~= nil,
	"UIKit sheets map native detents")
t.expect(src:find("function UIKit.confirm", 1, true) ~= nil
		and native:find("UIAlertController", 1, true) ~= nil,
	"UIKit confirmations use native UIAlertController")
t.expect(bridge:find('{"_presentSheet", bridge_UIKitPresentation_presentSheet}', 1, true) ~= nil
		and bridge:find('{"_dismiss", bridge_UIKitPresentation_dismiss}', 1, true) ~= nil
		and bridge:find('{"_confirm", bridge_UIKitPresentation_confirm}', 1, true) ~= nil,
	"UIKit presentation bridge is registered")
t.expect(navigation:find("UIBarButtonSystemItemDone",1,true) and navigation:find("UIBarButtonSystemItemCancel",1,true),
	"native toolbar Done and Cancel use system items")
t.expect(hosting:find("prefersInterfaceOrientationLocked",1,true) and hosting:find("setNeedsUpdateOfPrefersInterfaceOrientationLocked",1,true),
	"window orientation locks use the current native scene API")

local makefile = assert(io.open("Makefile", "r")):read("*a")
local imports = makefile:match("IOS_LUA_LOOKUP_SYMBOLS = (.-)comma :=")
local target = makefile:match("build/UIKit%.dylib:(.-)uikit:")
t.expect(imports and imports:find("_luaL_checkoption", 1, true),
	"the UIKit module imports sheet option validation from its Lua host")
t.expect(target and target:find("-framework UniformTypeIdentifiers", 1, true),
	"the UIKit module links the document importer's native content types")

os.exit(t.summary() and 0 or 1)
