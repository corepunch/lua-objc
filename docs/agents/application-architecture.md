---
layout: default
title: Application architecture
---

# Application architecture

lua-objc applications use a small Laravel-style MVC boundary around native
AppKit/UIKit controls:

```text
apps/<app>/
  init.lua              entry point; returns the controller class
  Model.lua             domain state, queries, validation, mutations
  Controller.lua        screen coordination, navigation, callbacks
  views/                etlua templates and partials only
```

This is a responsibility boundary, not a requirement to reproduce Laravel's
service container or request lifecycle. The useful rule is the same one used
by Laravel and conventional PHP MVC applications: domain code should be
testable without the framework, controllers should coordinate rather than
own presentation, and templates should describe presentation rather than
perform business work.

## Entry point

`init.lua` is deliberately boring. The framework loads the returned class,
instantiates it, and calls `createWindow()`.

```lua
-- apps/mail/init.lua
return require("apps.mail.Controller")
```

Do not start an event loop, construct a window, or build a view tree in
`init.lua`.

## Models

Each substantial screen or feature has its own model module. A model owns
plain Lua data and domain operations:

```lua
-- apps/mail/Model.lua
local Model = {}

function Model.byMailbox(mailboxId)
	-- query and normalize domain data
end

function Model.markRead(messageId)
	-- validate and mutate domain state
end

return Model
```

Models must not require `AppKit`, `UIKit`, `ns`, `ui.xml`, or native userdata.
They should be usable from a headless test. Inject a focused service for IO,
clocks, persistence, or HTTP when a model needs those boundaries; do not make
the model reach into a global native runtime.

For a large app, split models by bounded feature (`InboxModel`,
`SettingsModel`, `SessionModel`) instead of creating one global model that
knows every screen. A model may expose a module table or an instance, but the
controller should depend on the smallest useful interface.

## Controllers

Controllers coordinate one screen or one cohesive flow. They may prepare
plain template data, render templates, retain returned refs, bind actions,
update native list data, and perform navigation. They do not define visual
hierarchies.

```lua
local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("apps.mail.Model")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model, refs = {} }, Controller)
end

function Controller:createWindow()
	local config, refs = xml.renderFile(
		"apps/mail/views/Window.etlua", self:windowData(), ns)
	self.refs = refs or {}
	self:bindActions()
	self.window = ns.Window(config)
	return self.window
end

return Controller
```

Keep each controller focused. A window with a sidebar, list, and detail flow
can have a window controller that coordinates child controllers, but do not
put every screen's queries, actions, and callbacks in one application-wide
controller. When a feature has its own lifecycle, state, or navigation, give
it its own `Model.lua`, `Controller.lua`, and templates.

## Views and etlua syntax

Views are `.etlua` files. They contain XML-shaped native view descriptions,
etlua expressions, loops, and partials. They do not contain controller code,
native construction helpers, or business mutations.

```etlua
<!-- apps/mail/views/MessageRow.etlua -->
<HStack spacing="8" padding="10" ref="row">
    <VStack flexGrow="1" spacing="2">
        <Label text="<%= message.from %>" weight="semibold" />
        <Label text="<%= message.subject %>" color="secondary" truncation="tail" />
    </VStack>
    <Label text="<%= message.date %>" color="secondary" />
</HStack>
```

Repeated structure belongs in an etlua loop or partial:

```etlua
<VStack spacing="8">
<% for _, item in ipairs(items) do %>
    <% partial("views/partials/Item.etlua", { item = item }) %>
<% end %>
</VStack>
```

Render with:

```lua
local view, refs = xml.renderFile("apps/mail/views/MessageRow.etlua", data, ns)
```

The renderer injects the platform module. The same template can target
AppKit or UIKit when it uses the shared XML vocabulary. Use `ref="name"` for
the small amount of imperative wiring a controller needs after rendering.
That ref is an attachment point, not permission to recreate the view tree in
Lua.

`partial(path, data)` reuses a fragment. `extends(path, data)`, `block(name,
content)`, and `yield(name)` provide template inheritance. Keep conditions
and loops that choose presentation in the template; keep decisions about
what the data means in the model or controller.

## Screen lifecycle and ownership

Lua owns model/controller state. Native parents own mounted views. A Lua handle
to a native object is a retained, interned proxy: asking for the same native
object returns the same Lua userdata while it is alive. Objects received only
for a callback—such as a sender, event, or reused table cell—are borrowed and
must not be retained by a model.

Callbacks are state-bound `LuaReg` registrations. A native target retains the
registration, and the current `ns.Scope` can dispose it when a screen ends.
Use a scope for screen callbacks, timers, watchers, and requests:

```lua
local scope = ns.Scope.push()
-- render and bind this screen while scope is current
-- scope:close() on window close, unmount, or reload
```

`Scope` is the lua-objc approximation of the conditional reachability idea
behind Apple's JavaScriptCore `JSManagedValue`: a native edge is reported and
scoped instead of blindly retaining a script value forever. It is not
JavaScriptCore, and it does not make arbitrary Lua/native cycles collectible.
Dispose the scope deterministically, especially before replacing a screen or
Lua state. See [runtime ownership](../../ARCHITECTURE.md#object-and-state-ownership)
for the native details.

## What not to do

- Do not call `ns.Window` from a component or model. Only the app entry flow
  creates the window.
- Do not assemble `VStack`, `HStack`, lists, or detail panes in a controller.
  Put that structure in `views/*.etlua`.
- Do not create one controller or model for the entire application. Split by
  screen or cohesive feature and compose controllers when necessary.
- Do not put native handles in models or pass `ns` into model constructors.
- Do not fake native controls with labels, emoji, drawing, or custom shadows.
- Do not use sleeps to represent loading. Use the native loading state and
  explicit loaded, empty, error, selected, and disabled states.

## Testing contract

Test models and controller data preparation with headless Lua tests. Test XML
templates through `xml.renderFile` and assert refs, tags, and state branches.
Use native bridge tests for construction, mutation, layout, ownership, and
callback teardown. Use screenshots and layout dumps for visual changes. A
change is complete when it preserves the MVC boundary and has a fast test for
the behavior it changes.
