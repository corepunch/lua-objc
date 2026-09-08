# SwiftUI parity coverage contract

Status values are intentionally conservative: an exported surface starts as
`implemented-unverified`, and a fixture is not `passing` until native behavior,
geometry, appearance, and applicable interaction evidence are recorded.

## Inventory snapshot

This is the P0 inventory from the current source tree. The Lua constructor list
is the public visual surface; native bridge symbols are implementation support,
not additional user-facing controls. Data-only services are excluded.

| Family | Lua API | XML | AppKit | UIKit | SwiftUI mapping | Initial status |
|---|---|---:|---:|---:|---|---|
| Window | `Window`, `Panel` | `Window` | yes | `Window`/hosting | `WindowGroup`, `sheet`/window | implemented-unverified |
| Layout | `VStack`, `HStack`, `HSplit`, `VSplit`, `ScrollView`, `Spacer`, `Group`, `ForEach` | `VStack`, `HStack`, `ZStack`, `HSplit`, `Spacer` | no `ZStack` export; yes other listed primitives | no `HSplit` export; `ZStack` yes | stacks, `ZStack`, grouping, `ForEach` | implemented-unverified |
| Scrolling | `ScrollView` | `ScrollView` | yes | yes | `ScrollView` | implemented-unverified |
| Text | `Text`, `Title` | `Label`, `Text`, `Title` | yes | `Label`, `Text`, `Title` | `Text` | implemented-unverified |
| Text input | `TextField`, `SearchField`, `TextEditor` | `TextField`, `SearchField`, `TextEditor` | yes | `TextField`, `SearchField`, `TextEditor` | `TextField`, `SecureField`, `TextEditor`, searchable | implemented-unverified |
| Images | `Image`, `SystemImage`, `ImageViewer` | `Image`, `SystemImage` | yes | yes | `Image`, `Label` | implemented-unverified |
| Buttons | `Button`, `MenuItem` | `Button` | yes | yes | `Button`, `Menu` | implemented-unverified |
| Selection | `Toggle`, `Slider`, `Stepper`, `Picker` | all four plus `Option` | yes | `Toggle`, `Slider`, `Stepper`, `Picker` | controls and `Picker` | implemented-unverified |
| Feedback | `Separator`, `Divider`, `ProgressView`, `PageControl` | `Divider` | no `PageControl`; yes other listed primitives | no `ProgressView` export; yes other listed primitives | `Divider`, `ProgressView`, `PageControl` | implemented-unverified |
| Collections | `List`, `OutlineView` | `List`, `Column` | yes | `List` (table-shaped) | `List`, `Table`, `OutlineGroup` | implemented-unverified |
| Navigation | `TabView`, `NavigationStack` | `TabView`, `Tab` | `TabView` | both | `TabView`, `NavigationStack`, `NavigationSplitView` | implemented-unverified |
| Presentation | `present`, `dismiss`, focus helpers | none | yes | partial hosting | sheets, popovers, alerts, panels | implemented-unverified |
| Toolbar | `ToolbarItem`, toolbar config | `Toolbar`, `ToolbarItem` | yes | not equivalent | `ToolbarItem` and placements | implemented-unverified |
| Shapes/drawing | `PathView`, `Curve`, `LinearGradient`, `Chart` | `LinearGradient`, `Chart` | yes | partial | `Shape`, `Canvas`, `Chart`, gradients | implemented-unverified |

## XML vocabulary

The schema currently defines these tags: `VStack`, `HStack`, `ZStack`, `HSplit`,
`Spacer`, `PageControl`, `Divider`, `ScrollView`, `Label`, `Title`, `TextEditor`,
`TextField`, `Button`, `Toggle`, `Slider`, `Stepper`, `Option`, `Picker`,
`SystemImage`, `Image`, `LinearGradient`, `Column`, `List`, `ToolbarItem`,
`Toolbar`, `Window`, `Chart`, `TabView`, `Tab`, `Section`, `GroupBox`, `Form`,
`LabeledContent`, `ControlGroup`, and `DisclosureGroup`. `Text` and `Switch` are
aliases, not separate controls. Record tags such as `Column` and `Option` are
configuration nodes and are not counted as visual controls.

The table-shaped XML `List` is tracked separately from SwiftUI `List` and
`Table`; it must not be marked equivalent without evidence.

## Required fixture batches

The full fixture catalogue is represented by the batch IDs in
`tests/parity/manifest.json`. P0 seeds only the three P1 smoke fixtures. The
remaining A1–E families are explicitly incomplete until expanded and captured.

| Gate | Batches | P0 state |
|---|---|---|
| Core parity | A1–A5, B1–B5, C1, D1–D2, E | unassessed / incomplete |
| Common SwiftUI coverage | C2, D3 and missing members of A–D | unassessed / incomplete |
| Extension backlog | advanced scope in the plan | explicitly out of scope |
