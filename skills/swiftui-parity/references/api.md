# API mapping

Translate a SwiftUI Pro rule into a tag or attribute in `lua/ui/xml.lua`. If it is not in this file, it is a gap: read `gaps.md` and do not invent a workaround in the app.

`tests/swiftui_parity_contract.test.lua` asserts every tag below is in `xml.schema`.

## Use these, not the SwiftUI spelling

| SwiftUI Pro expects | lua-objc | Do not |
|---|---|---|
| `Text` | `<Label>` or alias `<Text>` | A second text control |
| `Label` with icon | `<Label systemImage="star.fill">` or `<Button systemImage="plus" title="Add">` | Emoji as the icon |
| `foregroundStyle()` | `color` on `<Label>` / `<Paragraph>`; `foregroundStyle` on `<Button>` | `foregroundColor`, or a free function |
| `tint()` | `tint` attribute | `accentColor` |
| `NavigationStack` | `<NavigationStack path="path" destinations="destinations">` | `NavigationView` |
| `navigationDestination(for:)` | `path` plus `destinations` in render data | A second router in the template |
| `Tab` / tab bar | `<TabView>` and `<Tab>` | `tabItem()` on a random child |
| Tab bar minimize | `minimizeBehavior="onScroll"` on `<TabView>` | A custom tab bar |
| Toolbar overflow | `<Toolbar>`, `<ToolbarItem>`, `<ToolbarSpacer>` | Hand-built toolbar chrome |
| `safeAreaInset` | `<SafeAreaInset>` | Hard-coded top padding as a safe area |
| `containerRelativeFrame` | `containerRelativeWidth` | `UIScreen.main` or a window-size global |
| `ContentUnavailableView` | `<ContentUnavailable>` | A custom empty stack of labels |
| Liquid Glass | `<GlassEffect style="regular\|clear">`, button `style="glass"` | Blur painted in a canvas |
| `searchable()` | `<SearchField>` | A `TextField` plus a magnifying emoji |
| `List` of rows | `<List>` with `<Column>`, or `<LazyVStack>` for custom cells | Eager `<VStack>` of unbounded rows |
| swipe actions | `<SwipeRow>` or `swipeLeading` / `swipeTrailing` on `<List>` | A drag gesture that deletes |
| reorder | `reorderable="true"` and `reorderContainer="action"` | A second drag library |
| `WebView` | `<WebView page="page">` | Browser chrome for an ordinary link |
| sheet | `<Sheet>` or `ns.presentSheet` | A `ZStack` pretending to be a sheet |

## Supported tags

Layout: `VStack`, `HStack`, `ZStack`, `HSplit`, `Spacer`, `ScrollView`, `Grid`, `GridRow`, `Section`, `GroupBox`, `Form`, `LabeledContent`, `ControlGroup`, `DisclosureGroup`, `FlowStack`, `LazyVStack`, `LazyVGrid`, `SafeAreaInset`.

Text and input: `Label`, `Title`, `Paragraph`, `TextField`, `SearchField`, `TextEditor`, `Hyperlink`, `Link`.

Controls: `Button`, `Toggle`, `Slider`, `Stepper`, `Picker`, `Option`, `DatePicker`, `ColorPicker`, `Menu`, `MenuItem`.

Collections and chrome: `List`, `Column`, `SwipeRow`, `OutlineView`, `Toolbar`, `ToolbarItem`, `ToolbarSpacer`, `TabView`, `Tab`, `TabAccessory`, `NavigationStack`, `NavigationLink`, `Page`, `Sheet`, `TopPalette`, `BottomPalette`, `Window`.

Feedback and media: `ContentUnavailable`, `ProgressView`, `Gauge`, `Divider`, `PageControl`, `Image`, `SystemImage`, `MaterialView`, `GlassEffect`, `GlassEffectContainer`, `LinearGradient`, `MeshGradient`, `WebView`, `Chart`.

`Text` and `Switch` are aliases, not separate controls. `Column`, `Option`, `ToolbarItem`, and `Tab` are records, not views.

## Common attributes

These apply through the shared layout pass, not as SwiftUI modifier chains: `padding`, `spacing`, `width`, `height`, `fillWidth`, `fillHeight`, `flexGrow`, `containerRelativeWidth`, `hidden`, `allowsHitTesting`, `background`, `tint`, `cornerRadius`, `clipsToBounds`, `ignoresSafeArea`, `contentMode`, `onTap`, `onDrag`, `onScroll`, `accessibilityLabel`, `id`.

`id` stores the view in `refs` and sets `accessibilityIdentifier`. `accessibilityLabel` is applied to any userdata view. There is no `accessibilityHint` attribute; do not emit one.
