_G.__headless = true

local ns = require("AppKit")
local t = require("TestKit")

-- Interned handles are identical Lua userdata.
local parent = ns.VStack {}
local child = ns.Text { "Same object", fixedWidth = 80 }
parent:add(child)
t.expect(rawequal(parent.subviews[1], parent.subviews[1]),
	"repeated reads intern to one handle")
t.expect(rawequal(child, parent.subviews[1]),
	"constructor handle matches interned child")

-- Scope.dispose unrefs the callback; later native invocation is a no-op.
local fired = 0
local scope = ns.Scope.push()
local button = ns.Button { "Go", action = function() fired = fired + 1 end }
ns._invokeAction(button)
t.assertEqual(fired, 1, "callback fires while registered")
scope:close()
ns._invokeAction(button)
t.assertEqual(fired, 1, "callback does not fire after Scope.dispose")

-- Replacing a text-field callback disposes the previous registration.
local seen = nil
local field = ns.TextField { value = "a", onChange = function(text) seen = text end }
ns._textFieldTestInput(field, "one")
t.assertEqual(seen, "one", "first text-field callback fires")
ns._textFieldCallbacks(field, function(text) seen = "two:" .. text end)
ns._textFieldTestInput(field, "x")
t.assertEqual(seen, "two:x", "replacement text-field callback fires")

-- to-be-closed Scope disposes on block exit.
local closed = 0
do
	local s <close> = ns.Scope.push()
	local b = ns.Button { "Close", action = function() closed = closed + 1 end }
	ns._invokeAction(b)
	t.assertEqual(closed, 1, "callback fires inside to-be-closed Scope")
end

-- Wrong-typed arguments raise without crashing (luaL_error hygiene).
local host = ns.Window { title = "scope-test", visible = false }
local ok, err = pcall(function()
	host:addTabbedWindow(ns.Button { "Other" })
end)
t.expect(not ok, "mismatched class is an error")
t.expect(tostring(err):find("Window", 1, true) ~= nil
	or tostring(err):find("NSWindow", 1, true) ~= nil,
	"type error names the expected class")

ok, err = pcall(function()
	require("AppKitNative")._picker({ function() end })
end)
t.expect(not ok, "unconvertible Lua value is an error")
t.expect(tostring(err):find("cannot convert", 1, true) ~= nil
	or tostring(err):find("Picker", 1, true) ~= nil,
	"conversion failure is reported")

-- Dead handles raise instead of crashing.
local released = ns.Text { "gone" }
ns._invalidateHandle(released)
ok, err = pcall(function()
	return released.text
end)
t.expect(not ok, "released handle is an error")
t.expect(tostring(err):find("released", 1, true) ~= nil,
	"dead handle error mentions release")

os.exit(t.summary() and 0 or 1)
