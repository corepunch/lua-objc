local t = require("TestKit")

local function read(path)
	local file = assert(io.open(path, "r"))
	local contents = file:read("*a")
	file:close()
	return contents
end

local runtime = read("src/appkit/runtime.m")
local constructors = read("src/appkit/constructors.m")
local bindings = read("src/appkit/bindings.m")
local structs = read("src/appkit/structs.m")
local uikitRuntime = read("src/uikit/runtime.m")
local uikitConstructors = read("src/uikit/constructors.m")
local uikitBridge = read("src/uikit/bridge.m")
local uikitPlatform = read("src/uikit/platform.m")

t.expect(not io.open("tools/AppKit.xml", "r"),
	"AppKit does not duplicate Objective-C metadata in XML")
t.expect(not io.open("tools/UIKit.xml", "r"),
	"UIKit does not duplicate Objective-C metadata in XML")
t.expect(runtime:find("valueForKey:", 1, true) ~= nil
		and runtime:find("setValue:", 1, true) ~= nil,
	"AppKit properties use Cocoa KVC")
t.expect(runtime:find("@interface LuaTextField", 1, true) ~= nil
		and runtime:find("setText:", 1, true) ~= nil,
	"semantic property names are native subclass accessors")
t.expect(runtime:find("@implementation NSView (LuaLayoutProperties)", 1, true)
		~= nil,
	"framework layout properties are inherited NSView accessors")
t.expect(constructors:find("[[LuaTextField alloc]", 1, true) ~= nil,
	"Lua exports instantiate the property-bearing subclass")
t.expect(bindings:find("MethodEntry WindowMethods", 1, true) ~= nil,
	"specialized non-property operations remain explicit native methods")
t.expect(structs:find("lua_objc.struct.NSSize", 1, true) ~= nil
		and structs:find("bridge_NSSize", 1, true) ~= nil,
	"Size userdata remains an explicit native value bridge")
t.expect(uikitRuntime:find(
		"@implementation UIView (LuaLayoutProperties)", 1, true) ~= nil,
	"UIKit layout properties are inherited KVC accessors")
t.expect(uikitConstructors:find(
		"bridge_UIKitControls_vstack", 1, true) ~= nil,
	"UIKit constructors are ordinary native source")
t.expect(uikitConstructors:find(
		"bridge_UIKitControls_textField", 1, true) ~= nil
		and uikitConstructors:find(
			"bridge_UIKitControls_progressIndicator", 1, true) ~= nil,
	"UIKit leaf controls use explicit native constructors")
t.expect(not uikitBridge:find("generated/", 1, true),
	"UIKit runtime has no generated bridge includes")
t.expect(not uikitBridge:find('{"_create"', 1, true)
		and not uikitBridge:find('{"_perform"', 1, true),
	"UIKit exports no generic construction or selector escape hatches")
t.expect(not uikitPlatform:find("NSInvocation", 1, true)
		and not uikitPlatform:find("NSClassFromString", 1, true),
	"UIKit implementation contains no generic runtime invocation fallback")

os.exit(t.summary() and 0 or 1)
