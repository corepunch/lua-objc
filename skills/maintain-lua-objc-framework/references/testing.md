# Framework testing

## Test routing

| Change | Primary coverage |
|---|---|
| AppKit bridge, userdata, layout, control, table, editor | `tests/bridge.test.lua` |
| Example entrypoint or public Lua composition | `tests/examples.test.lua` |
| IDE routing, recents, editor plugins | `tests/ide_headless.test.lua` |
| Embedded module packaging | assert `package.cpath` resolution in `tests/bridge.test.lua` |
| UIKit native code | build `UIKit.dylib` with the simulator SDK |
| Shared async/error code | run AppKit tests and build both platform dylibs |

`make test` discovers every `tests/*.test.lua`, builds the host, native provider,
AppKit, and IDEKit, then runs each file in its own process.

## Write a headless AppKit test

Use the native module and `TestKit`:

```lua
local ns = require("AppKit")
local t = require("TestKit")

local window = ns.Window {
	title = "Headless",
	width = 400,
	height = 300,
	visible = false,
	ns.Text "Content",
}

t.assertEqual(window.title, "Headless", "window retains its title")
os.exit(t.summary() and 0 or 1)
```

Use `visible = false` for direct window tests. Assert externally observable
native behavior through KVC properties, bridge inspection helpers, and public
methods:

- `t.assertEqual(view.property, expected, message)`
- `t.assertSize(view, width, height, message)`
- `t.assertThrows(function() ... end, message)`
- `bridge._viewSize(view)`
- `bridge._viewFrameInWindow(view)`
- list methods such as `addRow`, `removeRow`, `clearRows`, and `rowCount`

Test both success and invalid-input paths. For native controls, assert the
actual native property or class behavior rather than only checking non-nil.

## Smoke-test examples

Set headless mode before loading an example:

```lua
_G.__headless = true

local fn, loadError = loadfile("examples/example.lua")
if not fn then error(loadError) end
local ok, runtimeError = pcall(fn)
```

Add every new example or compatibility entrypoint to
`tests/examples.test.lua`. Headless mode suppresses window presentation; it
does not replace `visible = false` in focused window assertions.

## Test isolated canvas behavior

Use the private bridge only in framework tests:

```lua
local bridge = require("bridge")
local view, err = bridge._eval(source, true)
```

Cover valid source, syntax errors, runtime errors, state isolation, and the
native view returned across the state boundary. Do not retain Lua callbacks
from an isolated canvas state after its owner is cancelled.

## Test async services

Prefer deterministic synchronous coverage:

- verify public `async`, `sleep`, `fetch`, `json_parse`, and `fetch_json`
  functions exist;
- test `_jsonParse` with valid nested data and malformed JSON;
- test owner/cancellation behavior without network access where possible.

The normal headless suite does not run `NSApp run`, so scheduled timers and
network callbacks will not naturally complete. Do not add sleeps or live
network requests. Add a bounded run-loop test harness only when callback
delivery itself is the behavior under test, and guarantee cleanup on failure.

## Verify UIKit

First locate the simulator SDK:

```sh
xcode-select -p
xcrun --sdk iphonesimulator --show-sdk-path
```

If Command Line Tools are selected but full Xcode is installed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make uikit
```

Confirm the produced file is a simulator Mach-O and, for registration changes,
that expected native names are embedded:

```sh
file build/UIKit.dylib
strings build/UIKit.dylib | rg '^(_timerAfter|_httpGet|_jsonParse)$'
```

A successful dylib build checks Objective-C syntax, API availability, fragment
inclusion, and linkage. It does not exercise UIKit behavior. Do not claim
visual or runtime coverage unless an iOS host launches the module.

## Visual QA

For AppKit UI changes, launch every affected example and inspect real
screenshots. Resize smaller and larger, exercise supported loading/empty/error/
selected/disabled/long-text states, and check light and dark appearances,
keyboard focus, selection, truncation, toolbar rendering, and accessibility.

For UIKit UI changes, use an iOS host and Simulator. If the repository has no
host capable of loading `UIKit.dylib`, report that limitation explicitly after
the simulator build instead of treating compilation as visual verification.
