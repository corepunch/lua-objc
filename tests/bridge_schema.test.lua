local t = require("TestKit")

local function read(path)
	local file = assert(io.open(path, "r"))
	local contents = file:read("*a")
	file:close()
	return contents
end

local appkit = read("tools/AppKit.xml")
local uikit = read("tools/UIKit.xml")
local generated = read("src/appkit/generated/bridge_class_methods.m")
local properties = read("src/appkit/generated/bridge_props.m")
local structs = read("src/appkit/generated/bridge_structs.m")

for _, xml in ipairs { appkit, uikit } do
	t.expect(not xml:find("<method_group", 1, true),
		"bridge XML has no method groups")
	t.expect(not xml:find("<manual_entry", 1, true),
		"bridge XML has no manual entries")
	t.expect(not xml:find("<constructor", 1, true),
		"constructors are static class methods")
	t.expect(not xml:find("<callback_setter", 1, true),
		"callbacks are class methods")
	t.expect(not xml:find("c_func=", 1, true),
		"bridge XML derives C function names")
	t.expect(not xml:find("src=", 1, true),
		"bridge XML does not encode source locations")
end

t.expect(appkit:find('<class name="NSWindow"', 1, true) ~= nil,
	"window methods belong to NSWindow")
t.expect(appkit:find('<struct name="NSSize">', 1, true) ~= nil,
	"native value userdatas are declared in bridge XML")
t.expect(appkit:find(
		'<property name="size" type="NSSize" native="contentSize"',
		1, true) ~= nil,
	"Window.size is declared as a class property")
t.expect(generated:find("luaL_checknumber(L, 2)", 1, true) ~= nil,
	"method arguments generate Lua number validation")
t.expect(generated:find("luaL_checkstring(L, 2)", 1, true) ~= nil,
	"method arguments generate Lua string validation")
t.expect(generated:find("bridge_NSWindow_setContentSize", 1, true) ~= nil,
	"C wrapper names derive from class and method names")
t.expect(generated:find("[self setHidden:hidden]", 1, true) ~= nil,
	"typed methods generate their Objective-C message send")
t.expect(generated:find(
		"[self addSubview:view positioned:positioned relativeTo:relativeTo]",
		1, true) ~= nil,
	"argument names generate Objective-C selector labels")
t.expect(properties:find("push_NSSize", 1, true) ~= nil
		and properties:find("check_NSSize", 1, true) ~= nil,
	"class properties generate native userdata getters and setters")
t.expect(structs:find("lua_objc.struct.NSRect", 1, true) ~= nil,
	"NSRect userdata support is generated")
t.expect(generated:find("luaL_checkoption", 1, true) ~= nil
		and generated:find("NSWindowTabbingModeDisallowed", 1, true) ~= nil,
	"Objective-C enum arguments use generated luaL_checkoption mapping")

os.exit(t.summary() and 0 or 1)
