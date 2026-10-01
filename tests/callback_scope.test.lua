_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

-- A scan updates a page's controls inside its own timer callback. Their
-- native selection callbacks must not take ownership of its next timer.
local windowScope = ns.Scope.push()
local pageScope = ns.Scope.new()
local pageButton = ns.Scope.withScope(pageScope, ns.Button, {"Select", action = function()
	t.assertEqual(ns.Scope.current(), pageScope, "native callback exposes its owning scope to Lua")
end})
local nextButton, fired = nil, 0
local scanButton = ns.Button {"Poll", action = function()
	ns._invokeAction(pageButton)
	t.assertEqual(ns.Scope.current(), windowScope, "nested page callback restores scan scope")
	local transient = ns.Scope.new()
	ns.Scope.withScope(transient, function() end)
	t.assertEqual(ns.Scope.current(), windowScope, "template scope restores native callback ownership")
	nextButton = ns.Button {"Next poll", action = function() fired = fired + 1 end}
end}
local otherWindowScope = ns.Scope.push()
ns._invokeAction(scanButton)
t.assertEqual(ns.Scope.current(), otherWindowScope, "callback restores caller's window scope")
local failing = ns.Scope.withScope(pageScope, ns.Button, {"Fail", action = function() error("expected callback failure") end})
ns._invokeAction(failing)
t.assertEqual(ns.Scope.current(), otherWindowScope, "failed callback also restores caller's window scope")
pageScope:dispose()
otherWindowScope:close()
ns._invokeAction(nextButton)
t.assertEqual(fired, 1, "leaving a page cannot cancel work started by the window")
windowScope:close()
ns._invokeAction(nextButton)
t.assertEqual(fired, 1, "window close still cancels its work")
os.exit(t.summary() and 0 or 1)
