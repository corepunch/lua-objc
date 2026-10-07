# Navigation and presentation

- Use `<NavigationStack>`. Do not emit `NavigationView`.
- Value destinations are `path` and `destinations` attributes. Both names are keys in render data; the renderer resolves them. Register a destination once for a data type on that stack.
- Do not mix a path-driven stack with ad-hoc `NavigationLink(destination:)` style pushes in the same hierarchy. `<NavigationLink>` exists; use it only as the bridge documents, not as a second router.
- `<NavigationStack>` accepts one content child, one `<Toolbar>`, and palette records. A second content child is an error.
- Tabs are `<TabView>` containing `<Tab>` records. Set `minimizeBehavior="onScroll"` for the iOS tab bar. One `<TabAccessory>` is the view above the tab bar.
- `<TopPalette>` and `<BottomPalette>` use public placement unless `enablePrivateNavigationPalettes="true"`. Private palettes must cite `docs/PRIVATE_API_RESEARCH.md`. `LazyLayout` is research only; do not use it.
- Sheets: `<Sheet>`, or UIKit `ns.presentSheet(content, { detents = { "medium", "large" }, dragIndicator = true })`. AppKit uses a native sheet window. Attach the sheet to the presenting controller, not to a button buried in overflow chrome.
- Alerts and confirmation dialogs are native presentations from the controller. Do not build them as a `ZStack`.
- Ordinary links open in the platform browser. `<WebView page="page">` is for an embedded browsing workflow. `page` is a render-data key, not the native view owner.
