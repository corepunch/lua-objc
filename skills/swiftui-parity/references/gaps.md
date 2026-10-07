# Gaps

Load this only when a SwiftUI Pro rule has no lua-objc spelling, or when a review is about to invent one. A gap is not permission to substitute emoji, a canvas, or a second framework.

Not in this bridge, as of the schema contract:

- `Binding(get:set:)`, `@State`, `@Observable`, `onChange(of:)`.
- `withAnimation`, matched geometry, custom `transition`, `symbolEffect`.
- `ViewThatFits`, `ConcentricRectangle`, `containerRelativeFrame` beyond `containerRelativeWidth`.
- iPhone Duo hinge, reserved regions, vertical toolbar edge, `ArrangementView`.
- `foregroundStyle()` as a modifier chain. The string attribute on `<Label>` is the supported part.
- `accessibilityHint`, `accessibilityRole`, Dynamic Type size names such as `extraLarge` as XML attributes.
- `ContentUnavailableView.search` helper. Pass the term in from the controller.
- `NavigationView`, `tabItem()`, `navigationBarHidden()`.
- SwiftUI `List` of arbitrary row views. Use `LazyVStack` or a table `List`.
- `LazyLayout` and private navigation palettes without the explicit flag and the private-API note.

When a missing tag is required, extend `xml.registry` in the framework and add the tag to `tests/swiftui_parity_contract.test.lua` in the same change. Do not patch the app.
