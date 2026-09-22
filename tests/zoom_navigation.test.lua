_G.__headless = true
package.path = "./?.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local t = require("TestKit")
local Transition = require("ui.transition")
local Navigation = require("ui.navigation")

local ns = Transition.Namespace.new("cover")
t.assertEqual(ns.name, "cover", "namespace keeps its name")

local source = { kind = "source-view" }
local dest = { kind = "dest-view" }
ns:registerSource("cover", source)
ns:registerDestination("cover", dest, { transition = "zoom", toolbarVisibility = "hidden", ignoresSafeArea = true })

t.expect(ns:hasPair("cover"), "source and destination share an id")
t.assertEqual(ns:source("cover"), source, "namespace resolves the source view")
t.assertEqual(ns:destination("cover"), dest, "namespace resolves the destination view")

local srcMeta = Transition.sourceOf(source)
t.assertEqual(srcMeta.id, "cover", "source metadata stores the id")
t.assertEqual(srcMeta.namespace, ns, "source metadata stores the namespace")

local destMeta = Transition.destinationOf(dest)
t.assertEqual(destMeta.transition, "zoom", "destination requests zoom")
t.assertEqual(destMeta.toolbarVisibility, "hidden", "destination can hide the toolbar")
t.expect(destMeta.ignoresSafeArea == true, "destination can ignore the safe area")

Transition.setReduceMotion(false)
local zoomOpts = Transition.pushOptions("cover", ns)
t.assertEqual(zoomOpts.transition, "zoom", "zoom is used when Reduce Motion is off")

Transition.setReduceMotion(true)
local pushOpts = Transition.pushOptions("cover", ns)
t.assertEqual(pushOpts.transition, "push", "Reduce Motion falls back to a plain push")
t.expect(not Transition.shouldZoom(), "shouldZoom is false under Reduce Motion")
Transition.setReduceMotion(false)

local nav = Navigation.new()
nav:push("Root")
nav:registerPresented("showDetail", function() return dest end, {
	sourceId = "cover",
	namespace = ns,
	transition = "zoom",
})
t.expect(not nav:isPresented("showDetail"), "detail starts dismissed")
nav:setPresented("showDetail", true)
t.expect(nav:isPresented("showDetail"), "isPresented toggles the destination on")
t.assertEqual(nav:current().name, "showDetail", "presenting pushes the destination")
t.assertEqual(nav:current().data.sourceId, "cover", "push carries the source id")
nav:setPresented("showDetail", true)
t.assertEqual(#nav.stack, 2, "setting the same presented flag is idempotent")
nav:setPresented("showDetail", false)
t.expect(not nav:isPresented("showDetail"), "dismissing clears isPresented")
t.assertEqual(nav:current().name, "Root", "dismiss pops back to the source screen")

os.exit(t.summary() and 0 or 1)
