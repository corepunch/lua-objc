# Navigation patterns

Navigation uses the shared XML renderer and a native host. The controller owns
model state and actions; it may render a destination template and pass that
rendered view to the existing native stack. It must not build a view tree or
create another window as a navigation shortcut.

## Native navigation stack

Use `<NavigationStack>` in a cross-platform `.etlua` template. The root and
destinations are rendered from templates. Keep a reference to the native stack
and use `ns.pushScreen` / `ns.popScreen` for page history:

```xml
<NavigationStack ref="navigation" title="Library">
  <VStack>
    <Button title="Open item" action="showItem" />
  </VStack>
</NavigationStack>
```

```lua
function Controller:showItem(id)
	local item = self.model:item(id)
	if not item then return end
	local destination = xml.renderFile("views/Item.etlua", {
		item = item,
		actions = self.itemActions,
	}, ns)
	ns.pushScreen(self.refs.navigation, item.title, function()
		return destination
	end)
end

function Controller:goBack()
	ns.popScreen(self.refs.navigation)
end
```

AppKit uses `NSPageController`; UIKit uses `UINavigationController`. The host
owns the transition and the Back behavior. Preserve domain state in the model,
not in a screen's temporary widget refs. See `docs/PROJECT_REFERENCE.md` for the
current `NavigationStack` API.

For data-driven destinations, use `require("ui.navigation").Path` and map a
stable value type to a controller-owned builder. The path contains model values,
never views. `push` adds a Back destination, `replace` removes the current route
for a one-way transition, and `reset` rebuilds the stack after logout or another
root change. Keep unrelated model state outside the path.

## Tabs and split views

Use `<TabView>` for native tab navigation where the registry supports the
platform. Use `<HSplit>` / a window sidebar for multi-column macOS and iPad
layouts. Do not recreate system tab or navigation bars with segmented controls,
custom drawing, or private classes. Check the XML vocabulary and platform
reference for the exact properties supported by the current host.

Use public `UINavigationItem`, toolbar, and search APIs for navigation chrome.
`<TopPalette>` and `<BottomPalette>` use public `titleView` and `UIToolbar` by
default. The experimental `enablePrivateNavigationPalettes="true"` option is
restricted to the iOS 26.5 runtime. Private APIs can change without notice,
break accessibility or layout, and cause App Review rejection. Do not suggest
that option unless the user explicitly requests private APIs and you show this
risk paragraph. See
[`docs/PRIVATE_API_RESEARCH.md`](../../../../docs/PRIVATE_API_RESEARCH.md).

## Sheets

UIKit exposes `ns.presentSheet(content, { detents = { "medium", "large" },
dragIndicator = true })` backed by `UISheetPresentationController`. AppKit
exposes `ns.Sheet` and `ns.presentSheet(sheet, parent)` as a native sheet-window
equivalent. Build sheet content from `.etlua` templates.

Choose navigation by user intent: push when the user should go deeper and return
with Back, a sheet for a temporary focused task, tabs for peer destinations,
and replacement only for a genuine one-way transition such as completing setup.
Keep a return path when the user expects one.
