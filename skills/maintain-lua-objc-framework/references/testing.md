# Framework testing

## Test routing

| Change | Primary coverage |
|---|---|
| AppKit bridge, userdata, layout, control, table, editor | `tests/bridge.test.lua` |
| XML tag registration, etlua rendering | `tests/xml.etlua.test.lua` |
| Native layout dump output | `tests/layout_dump.test.lua` |
| Example entrypoint or public Lua composition | `tests/examples.test.lua` |
| App controller construction and workspace state | per-app tests (e.g. `tests/stocks_workspace.test.lua`, `tests/mail_workspace.test.lua`) |
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

## Test app controllers (in-process, no subprocess)

Test controllers by requiring them directly, instantiating, and calling
`createWindow()`:

```lua
_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Controller = require("examples.mail.Controller")

local controller = Controller.new()
local window = controller:createWindow()
local state = window:workspaceState()

t.expect(state ~= nil, "mail window uses native workspace composition")
t.expect(state.itemCount == 3, "mail window has sidebar, message list, and detail")
t.expect(state.nativeSidebar, "mail uses AppKit semantic sidebar")
```

**Never spawn `./lua-objc <dir>` subprocesses in tests.** Subprocess tests
introduce run-loop timing races between `ns.sleep()` and the
`dispatch_after(0.5)` calls in `src/main.m` and `src/appkit/editor.m` that
activate windows and set key/main state. In-process headless tests are
deterministic, faster, and avoid these races entirely.

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

## Test XML templates and tags

Verify template rendering with `xml.render()` or `xml.renderFile()`:

```lua
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- Render a template string
local view = xml.render([[
<VStack spacing="8">
    <Label text="Hello" size="14" weight="bold" />
</VStack>
]], {}, ns)

t.expect(view ~= nil, "template renders a non-nil view")
t.assertEqual(view.spacing, 8, "layout props are applied")
```

When adding a new XML tag, add coverage for:
- The tag produces a valid view userdata
- Attributes are coerced (numbers, booleans)
- Layout props are forwarded
- Children are included correctly
- Error paths (missing required attributes, unknown tags)

## Test layout dumps

Layout dump tests verify the native view hierarchy without pixel inspection:

```lua
local t = require("TestKit")
local path = os.tmpname() .. ".xml"
local cmd = string.format(
    "./lua-objc --dump-layout=%q examples/stocks/init.lua >/dev/null 2>&1", path)
local ok = os.execute(cmd)
t.expect(ok == true or ok == 0, "layout dump command exits successfully")

local f = io.open(path, "r")
local dump = f and f:read("*a") or ""
if f then f:close() end
os.remove(path)

t.expect(dump:find('<View class="', 1, true) ~= nil,
    "layout dump contains native view nodes")
t.expect(dump:find('cropped="', 1, true) ~= nil,
    "layout dump reports cell cropping")
```

Key assertions for layout dumps:
- Native class names appear (`NSSearchField`, `LuaPathView`, etc.)
- Specific text content is present in the expected context
- Column IDs and cell positions match expectations
- `cropped`, `ellipsis`, `outsideParent` flags are correct for known-good layouts
- Content that should fit reports `cropped="false" ellipsis="false"`
- Content that should truncate reports `insufficientTextSpace="true" ellipsis="true"`

## Test isolated canvas behavior

Use the private bridge only in framework tests:

```lua
local bridge = require("AppKitNative")
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

Prefer `--dump-layout` for initial verification — it catches overflow, clipping,
and truncation without human inspection. Use screenshots to confirm the
dump's findings and catch issues the dump can't express (color, contrast,
spacing feel, animation).

For UIKit UI changes, use an iOS host and Simulator. If the repository has no
host capable of loading `UIKit.dylib`, report that limitation explicitly after
the simulator build instead of treating compilation as visual verification.
