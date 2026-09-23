# Gestures and haptics

Gesture recognition runs in the native view layer. Callbacks should update
model state or request a native control action; never drive a frame loop from
Lua.

## Tap

`onTap` (or the AppKit spelling `onClick`) calls a Lua action when a view is
tapped/clicked. The callback receives no arguments. XML action names resolve
through the render data `actions` table:

```xml
<Button title="Save" onTap="save" />
<VStack onTap="selectSection"><Label text="Inbox" /></VStack>
```

## Drag

`onDrag` attaches a native pan recognizer on AppKit and UIKit. Its callback
receives a table with `state` (`began`, `changed`, `ended`, or `cancelled`),
`location`, `translation`, and `velocity`; the last three contain `x` and `y`
values in points. The translation is total displacement since the gesture
began. Use the velocity when choosing a final model state; do not assign a
position every event to imitate a native spring.

```xml
<Image ref="photo" systemImage="photo" onDrag="movePhoto" />
```

```lua
function Controller:movePhoto(event)
	if event.state == "ended" then
		self.model:movePhoto(event.translation, event.velocity)
	end
end
```

Long press, swipe, pinch, rotation, simultaneous gesture priority, and
request-driven recognizer states are not part of the current XML vocabulary.
Use native controls with built-in behavior where the framework does not expose
the recognizer you need.

## Haptics and Reduce Motion

`require("ui.haptics")` calls the platform haptic engine for impact, selection,
and notification feedback. Requests return without effect when the device has
no provider or Reduce Motion is enabled. Haptics supplement accessible visual
and spoken feedback; they do not replace it.

```lua
local haptics = require("ui.haptics")
haptics.selection()
if haptics.isReduceMotionEnabled() then
	-- Use a state change without a zoom or decorative transition.
end
```

UIKit navigation and sheet transitions query the system Reduce Motion setting.
Native table row updates retain platform animation behavior. There is no
general property animation, matched-geometry, or Lua-driven spring API.
