_G.__headless = true
package.path = "./?.lua;./lua/?.lua;" .. package.path

local t = require("TestKit")
local haptics = require("ui.haptics")
local Transition = require("ui.transition")

local requests = haptics._setTestEnvironment(false, true)
haptics.impact("light")
haptics.selection()
haptics.notification("success")
t.assertEqual(#requests, 3, "native haptic operations are requested")
t.assertEqual(requests[1][1], "_hapticImpact", "impact uses native provider")
t.assertEqual(requests[2][1], "_hapticSelection", "selection uses native provider")
t.assertEqual(requests[3][1], "_hapticNotification", "notification uses native provider")
t.expect(haptics.isAvailable(), "availability reflects the provider")

requests = haptics._setTestEnvironment(true, true)
t.expect(haptics.isReduceMotionEnabled(), "system motion preference is observable")
t.expect(not Transition.shouldZoom(), "Reduce Motion disables zoom transitions")
haptics.impact("heavy")
haptics.selection()
t.assertEqual(#requests, 0, "Reduce Motion suppresses decorative haptic requests")

Transition.setReduceMotion(false)
t.expect(Transition.shouldZoom(), "explicit override supports controlled test scenarios")
Transition.setReduceMotion(nil)
t.expect(not Transition.shouldZoom(), "clearing the override restores system preference")
haptics._setTestEnvironment(nil)

os.exit(t.summary() and 0 or 1)
