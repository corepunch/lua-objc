# Motion

Use platform-owned navigation and presentation transitions. UIKit navigation
and sheet transitions follow the system Reduce Motion preference; AppKit owns
its native window sheet behavior. Native List row insertion and removal keep
the platform's row animations.

There is no general implicit animation API, matched-geometry implementation, or
Lua frame loop. Do not call undocumented `view:animate(...)` methods or assign
`frame` on each drag event. For an interactive drag, use the native `onDrag`
event's translation and velocity to update model state, then let the native
container perform the resulting layout.

Keep static chrome and dense data still. Add motion only when it helps explain a
state change, keep it interruptible, and use system navigation or sheet APIs
instead of building a custom transition. See [`gestures.md`](gestures.md) for
the current `onTap`, `onDrag`, haptics, and Reduce Motion APIs.
