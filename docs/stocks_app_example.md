# Stocks app example

This is the best current example of the lua-objc story: a real AppKit-style app
that renders instantly from Lua and XML, with no compile cycle between edits and
run.

![Stocks app example](stocks-example.png)

## Why this matters

This project started from a very specific frustration: SwiftUI development often
feels like a slow, fragile loop instead of a fast design tool.

> "Literally every time I make a change the SwiftUI previews break, requires me
to restart, and give unexpected errors..." — Reddit, r/iOSProgramming
>
> "The preview canvas crashes more than it works." — Reddit, r/SwiftUI
>
> "Full app builds take 30+ seconds. That latency kills the feedback loop." —
> Reddit, r/SwiftUI
>
> "In reality, the process would take minutes and simulator often stuck in black
> screen... I can go on and on about how slow SwiftUI preview is." — Reddit,
> r/iOSProgramming

The overall pattern is consistent across the ecosystem: Xcode builds are slow,
SwiftUI previews are unreliable, and the embedded simulator stalls or blacks out
often enough to destroy iteration speed. That is the reason lua-objc exists: to
replace a fragile, compile-heavy feedback loop with immediate Lua execution and a
native runtime that stays fast and predictable.

The idea is simple and powerful:

- edit Lua or etlua templates
- rerun the app immediately
- keep the same app logic while the platform remains native and fast
- target macOS now, then extend the same architecture to iPhone, iPad, and other
  devices without forcing a full compile-run loop
- pair this with AI workflows and voice-driven app building as the next step in
  product creation

This is not a mock. It is a native-feeling AppKit workspace with a sidebar, a
search field, list rows, and detail content rendered through the runtime’s
declarative stack.

## App structure

The repo recommends this layout for every app:

```text
examples/<app>/
  init.lua        -- entry point, returns the controller class
  Model.lua       -- pure data and domain logic
  Controller.lua  -- binds model -> view state and actions
  views/          -- etlua templates for each scene or section
```

This keeps app logic testable and separates the declarative UI from business data.

## Example: app entry point

```lua
-- examples/stocks/init.lua
return require("examples.stocks.Controller")
```

This is intentionally thin. The host framework instantiates the controller and
opens the window; the app itself does not self-start.

## Example: data model in Lua

```lua
-- examples/stocks/Model.lua
local Model = {}

Model.symbols = { "^IXIC", "AAPL", "MSFT", "GOOG", "NVDA" }

function Model.sampleStock(symbol)
	return {
		symbol = symbol,
		name = "NASDAQ Composite",
		price = 232.15,
		changePct = 1.43,
		chartData = { 120, 121, 119, 122, 123, 124, 126 },
	}
end

return Model
```

This code remains plain Lua and is easy to test headlessly. No UI runtime or
window is required just to reason about market data.

## Example: controller wiring

```lua
-- examples/stocks/Controller.lua
local ns = require("AppKit")
local Model = require("examples.stocks.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		stockData = {},
		selectedSymbol = "^IXIC",
	}, Controller)
end

function Controller:updateSidebar()
	self.stockList:replaceRows(self:visibleRows())
end

function Controller:createWindow()
	self.stockList = ns.List {
		style = "sourceList",
		columns = {
			{ id = "symbol", title = "Symbol", width = 131 },
			{ id = "price", title = "Quote", width = 96 },
		},
	}

	self.window = ns.Window {
		sidebar = self.stockList,
		content = ns.Text "Stock detail",
	}

	return self.window
end
```

The controller owns the actions and state, while the native AppKit widgets remain
in the background. This is the same pattern you would follow for dashboards,
editors, mail clients, or productivity tools.

## Example: declarative etlua view composition

```xml
<!-- examples/stocks/views/Window.etlua -->
<Window title="Stocks" width="1100" height="680">
	<SplitView>
		<VStack id="sidebar" width="340">
			<SearchField placeholder="Search" />
			<List id="stockList" flexGrow="1" />
		</VStack>
		<VStack id="content" flexGrow="1">
			<Label text="NASDAQ Composite" weight="bold" size="24" />
		</VStack>
	</SplitView>
</Window>
```

This XML layer is declarative and lightweight. It expresses structure and
layout, while the Lua controller fills in the live state and behavior.

## A future direction

This architecture is a good base for a broader product vision:

- build on macOS today
- reuse the same app model on iPhone and iPad
- use AI-assisted generation to compose UIs from intent and context
- use voice input to speak commands, filters, and actions directly into the app
- move toward a no-compile, live-app workflow across devices

The point is not just writing a small app faster. The point is making software
creation feel like designing and talking to the runtime instead of waiting for a
full compile cycle.

## Run it

```sh
make
./lua-objc examples/stocks
```

Or capture a screenshot:

```sh
make screenshot ARGS="examples/stocks/init.lua" OUT=/tmp/stocks.png
```
