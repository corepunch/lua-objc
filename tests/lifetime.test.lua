_G.__headless = true

local ns = require("AppKit")
local bridge = require("AppKitNative")
local t = require("TestKit")

local function collect()
	collectgarbage("collect")
	collectgarbage("collect")
end

-- 1. An unmounted view deallocs once its last handle is collected.
bridge._deallocReset()
do
	local v = ns.Text { "ephemeral" }
	bridge._watchDealloc(v)
end
collect()
t.assertEqual(bridge._deallocCount(), 1, "unmounted view deallocs after handle GC")

-- 2. A mounted view survives handle collection while its parent retains it.
bridge._deallocReset()
local parent = ns.VStack {}
do
	local child = ns.Text { "mounted" }
	bridge._watchDealloc(child)
	parent:add(child)
end
collect()
t.assertEqual(bridge._deallocCount(), 0, "mounted view survives handle GC")
t.assertEqual(#parent.subviews, 1, "parent keeps mounted child")
parent:clearContainer()
-- Drain autoreleased temporaries (e.g. the subviews NSArray) so the
-- detached child can dealloc.
bridge._runLoopTick(0.02)
collect()
t.assertEqual(bridge._deallocCount(), 1, "detached child deallocs after container clear")

-- 3. Closing a window disposes its scope (deterministic teardown).
-- Native ownership is unchanged: the window (owned by NSApp) keeps its
-- content alive, but every scope-rooted callback goes dead on close.
bridge._deallocReset()
local win = ns.Window { title = "lifetime-close", visible = false, ns.Text { "root" } }
local closeFired = 0
do
	local scope = ns.Scope.current()
	t.expect(scope ~= nil, "window pushes a current scope")
	local probe = ns.Button { "probe", action = function() closeFired = closeFired + 1 end }
	ns._invokeAction(probe)
	t.assertEqual(closeFired, 1, "window-scope callback fires before close")
	win:close()
	ns._invokeAction(probe)
	t.assertEqual(closeFired, 1, "window close disposes scope callbacks")
	probe = nil
end
collect()
-- The window is owned by NSApp (releasedWhenClosed=NO), so closing must
-- dispose callbacks without requiring native dealloc. Handles stay
-- collectable while native parents retain their children.
win = nil
bridge._runLoopTick(0.02)
collect()
t.assertEqual(bridge._deallocCount(), 0, "window close disposes without native dealloc")

-- 4. Two-window isolation: handlers bind to the firing scope, not the global.
do
	local winA = ns.Window { title = "A", visible = false }
	local scopeA = ns.Scope.current()
	local firedA = 0
	local buttonA
	do
		local s = scopeA
		ns.Scope.withScope(s, function()
			buttonA = ns.Button { "A", action = function() firedA = firedA + 1 end }
		end)
	end
	local winB = ns.Window { title = "B", visible = false }
	local scopeB = ns.Scope.current()
	local firedB = 0
	local buttonB
	ns.Scope.withScope(scopeB, function()
		buttonB = ns.Button { "B", action = function() firedB = firedB + 1 end }
	end)
	-- Fire A while B is current; any regs created inside must land in A.
	local innerFired = 0
	local inner
	do
		-- Replace A's action with one that builds a new button. The
		-- replacement must be created in A's scope, not B (current).
		ns.Scope.withScope(scopeA, function()
			buttonA = ns.Button { "A2", action = function()
				firedA = firedA + 1
				inner = ns.Button { "inner", action = function() innerFired = innerFired + 1 end }
			end }
		end)
	end
	ns._invokeAction(buttonA)
	t.assertEqual(firedA, 1, "A fires while B is current")
	t.expect(inner ~= nil, "handler creates inner button")
	-- Closing B must not dispose A's handler-created button.
	scopeB:close()
	winB:close()
	ns._invokeAction(buttonA)
	t.assertEqual(firedA, 2, "A survives B close (firing-scope affinity)")
	ns._invokeAction(inner)
	t.assertEqual(innerFired, 1, "handler-created button bound to A, not B")
	ns._invokeAction(buttonB)
	t.assertEqual(firedB, 0, "B callback disposed by B close")
	scopeA:close()
	winA:close()
	winA, winB, buttonA, buttonB, inner = nil, nil, nil, nil, nil
	collect()
end

-- 5. Per-screen scope: popped screens stop firing, root keeps working.
do
	local rootFired = 0
	local root = ns.Text { "root" }
	local nav = ns.NavigationStack { content = root, title = "Life" }
	local detailFired = 0
	local detailButton
	ns.pushScreen(nav, "Detail", function()
		detailButton = ns.Button { "detail", action = function()
			detailFired = detailFired + 1
		end }
		return ns.HostingController(ns.VStack { detailButton })
	end)
	t.assertEqual(nav.depth, 2, "pushScreen appends native page")
	ns._invokeAction(detailButton)
	t.assertEqual(detailFired, 1, "detail fires while mounted")
	ns.popScreen(nav)
	t.assertEqual(nav.depth, 1, "popScreen returns to root")
	ns._invokeAction(detailButton)
	t.assertEqual(detailFired, 1, "popped screen callback disposed")
	local rootButton
	do
		local s = ns.Scope.current()
		-- Root button was created before push; create a fresh one bound now.
		rootButton = ns.Button { "root", action = function() rootFired = rootFired + 1 end }
	end
	ns._invokeAction(rootButton)
	t.assertEqual(rootFired, 1, "root scope unaffected by pop")
	nav, detailButton, rootButton = nil, nil, nil
	collect()
end

-- 6. Scope prunes disposed entries instead of growing for window lifetime.
do
	local scope = ns.Scope.push()
	local b1 = ns.Button { "one", action = function() end }
	t.assertEqual(#scope.regs, 1, "scope holds one registration")
	local first = scope.regs[1]
	first:dispose()
	t.expect(first:isDisposed(), "disposed registration reports disposed")
	local b2 = ns.Button { "two", action = function() end }
	t.assertEqual(#scope.regs, 1, "adding prunes disposed entries")
	scope:close()
	t.expect(scope.closed, "closed scope reports closed")
	scope:close()
	t.expect(scope.closed, "double close stays closed")
	b1, b2 = nil, nil
	collect()
end

-- 7. Timer scheduled in a scope is cancelled by scope close.
do
	local scope = ns.Scope.push()
	local timerFired = 0
	bridge._timerAfter(0.02, function() timerFired = timerFired + 1 end)
	scope:close()
	bridge._runLoopTick(0.15)
	t.assertEqual(timerFired, 0, "timer cancelled by scope close")
	local scope2 = ns.Scope.push()
	local timerFired2 = 0
	bridge._timerAfter(0.02, function() timerFired2 = timerFired2 + 1 end)
	bridge._runLoopTick(0.15)
	t.assertEqual(timerFired2, 1, "timer fires while scope lives")
	scope2:close()
	collect()
end

-- 8. Retired-state callbacks are no-ops after dispose (replacement hygiene).
do
	local scope = ns.Scope.push()
	local seen = 0
	local button = ns.Button { "retire", action = function() seen = seen + 1 end }
	ns._invokeAction(button)
	t.assertEqual(seen, 1, "callback fires while live")
	scope:close()
	ns._invokeAction(button)
	t.assertEqual(seen, 1, "callback silent after scope close")
	button = nil
	collect()
end

os.exit(t.summary() and 0 or 1)
