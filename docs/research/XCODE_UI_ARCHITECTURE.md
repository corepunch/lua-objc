# Xcode UI Architecture Notes

> Reverse-engineering notes based on the macOS Accessibility hierarchy captured from Xcode on 25 July 2026, supplemented with public Apple documentation and inspection of Xcode bundle/framework artifacts reported online.
>
> **Important:** most classes prefixed `IDE`, `DVT`, `IBC`, `SourceEditor`, and `XR` are private implementation details. They are useful for understanding Xcode and for exploratory automation, but they are not stable APIs and may change between Xcode releases.

## 1. Executive summary

The inspected Xcode UI is a large AppKit application organized around a workspace window. The workspace window contains a top-level split-view layout whose major areas are represented by dedicated controller-owned views:

```text
IDEApplication
└── IDEWorkspaceWindow
    └── workspace root NSSplitView
        ├── navigator area
        └── editor area
            ├── editor content
            └── optional debug area
```

The screenshots show three recurring architectural patterns:

1. **Large structural regions are AppKit split views.** Xcode uses `NSSplitView`, private subclasses such as `DVTSplitView`, and controller-marked wrapper views such as `DVTEditorSplitView_ControlledBy_IDEEditorArea`.
2. **Feature-specific components are embedded inside those regions.** Examples include the Project Navigator, Source Editor, Debug Console, and Asset Catalog editor.
3. **Xcode is now a hybrid AppKit/SwiftUI application.** Traditional workspace chrome and editors expose AppKit classes, while newer surfaces—such as the intelligence/chat UI and Accessibility Inspector content—appear through `NSHostingView` and SwiftUI accessibility nodes.

This suggests that Xcode is not one monolithic custom canvas. It is closer to a host shell made from AppKit window/view-controller infrastructure, with many specialized editor and navigator plug-ins inserted into standard regions.

---

## 2. Evidence source and limitations

The screenshots were produced by Accessibility Inspector. That means the trees describe the **accessibility hierarchy**, not necessarily the exact `NSView` ownership tree. Accessibility may:

- omit non-accessible implementation views;
- flatten wrapper views;
- expose virtual rows or lazy SwiftUI nodes not present as individual persistent views;
- use generated accessibility proxies;
- report role names such as “group” or “split group” that are semantic rather than exact AppKit types.

However, many entries include their runtime class names, making the captures unusually useful for architectural inference.

Captured files:

- `Screenshot 2026-07-25 at 18.26.01.png`
- `Screenshot 2026-07-25 at 18.26.28.png`
- `Screenshot 2026-07-25 at 18.26.51.png`
- `Screenshot 2026-07-25 at 18.27.20.png`
- `Screenshot 2026-07-25 at 18.27.57.png`
- `Screenshot 2026-07-25 at 18.28.51.png`
- `Screenshot 2026-07-25 at 18.41.28.png`
- `Screenshot 2026-07-25 at 18.41.52.png`
- `Screenshot 2026-07-25 at 18.43.03.png`

---

## 3. Top-level application and workspace window

The root exposed by Accessibility Inspector is:

```text
Xcode (application) [IDEApplication]
└── Application — <current document> (standard window) [IDEWorkspaceWindow]
```

### `IDEApplication`

`IDEApplication` is Xcode's application-level object, apparently an `NSApplication` subclass or equivalent private application class. It represents the process-level shell rather than a project.

Likely responsibilities include:

- application lifecycle;
- global menus and commands;
- opening projects/workspaces;
- window coordination;
- extension and framework initialization;
- global preferences and services.

### `IDEWorkspaceWindow`

Each project/workspace is displayed in an `IDEWorkspaceWindow`. The screenshot title changes according to the active editor:

```text
Application — stb_truetype.h
Application — Assets.xcassets
```

This indicates that the window is persistent while the active editor context changes beneath it. Publicly observed Xcode bundle diffs also list an `IDEWorkspaceWindow.nib` inside `IDEKit.framework`, supporting the interpretation that the workspace window is an IDEKit-owned AppKit window loaded from a NIB.

The first structural child is:

```text
/Users/ICHERNA/Developer/presenter/Application.xcodeproj
(split group) [NSSplitView...]
```

The project path appears to label the workspace-root split group. This is the container from which the major workspace areas branch.

---

## 4. Workspace-area composition

The screenshots expose at least two major siblings below the workspace root:

```text
workspace root split group
├── navigator (group) [NSView_ControlledBy_IDENavigatorArea]
└── editor area (group) [DVTSplitView_ControlledBy_IDEEditorArea]
```

Xcode normally also has an inspector/utilities region on the trailing side, although it was not expanded in these captures. The inferred full arrangement is:

```text
IDEWorkspaceWindow
└── Workspace root
    ├── Navigator area                 IDENavigatorArea
    ├── Editor area                    IDEEditorArea
    │   ├── Editor split(s)
    │   └── Debug area, when visible
    └── Inspector / utilities area     likely another IDE-owned area controller
```

The class names include `_ControlledBy_...`, which strongly suggests Xcode uses controller-bound host views or private subclasses whose debugging/accessibility names identify their owning controller.

### Architectural interpretation

A useful conceptual model is:

```text
Window shell
  owns named IDE areas

Each area
  owns one or more split/container views

Each container
  hosts a selected feature implementation
  (navigator, source editor, asset editor, console, chat, etc.)
```

This is similar to a plug-in-oriented workbench architecture: stable regions remain in place, while editor-specific content is swapped according to the selected file and current mode.

---

## 5. Navigator area

The Project Navigator screenshot shows:

```text
navigator (group) [NSView_ControlledBy_IDENavigatorArea]
└── <empty description> (scroll area) [DVTScrollView]
    └── Project Navigator (outline) [DVTExplorableKit.DVTExplorerOutlineView]
        └── <empty description> (outline row) [NSOutlineRow]
            └── <empty description> (cell) [<NSTableViewCellMockElement> ...]
                ├── Application-Bridging-Header.h (text field)
                └── C Header Source () [DVTIconViewImageCell]
```

### `IDENavigatorArea`

`IDENavigatorArea` appears to own the entire left sidebar region, rather than one particular navigator. The selected navigator in this capture is the Project Navigator.

This distinction matters:

- **Navigator area:** persistent host region and selector infrastructure.
- **Project Navigator:** one navigator implementation placed inside that host.

Other standard Xcode navigator modes—symbols, find, issues, tests, debug, breakpoints, reports—would likely replace or reconfigure the area’s child content without replacing the entire workspace region.

### `DVTScrollView`

The project tree is wrapped in `DVTScrollView`, probably a Developer Tools (`DVT`) subclass of `NSScrollView` providing Xcode-wide behavior or styling.

### `DVTExplorerOutlineView`

The Project Navigator itself is exposed as:

```text
DVTExplorableKit.DVTExplorerOutlineView
```

This implies a reusable “explorer” subsystem, not a project-specific tree coded directly into `IDENavigatorArea`. The subsystem likely handles:

- hierarchical data presentation;
- expansion/collapse;
- selection;
- contextual menus;
- drag and drop;
- filtering;
- badges and status decorations;
- cell reuse.

The Swift-qualified style `DVTExplorableKit.DVTExplorerOutlineView` suggests at least this component comes from a named module/framework called `DVTExplorableKit`.

### Outline rows and cells

Rows appear as `NSOutlineRow`, while the cell appears through an accessibility mock object:

```text
<NSTableViewCellMockElement>
```

That is a reminder that Accessibility Inspector is showing a semantic representation. The visible file row contains at least:

- a text field for the file name;
- an icon cell, here identified as `DVTIconViewImageCell`.

The file-type description `C Header Source` is exposed separately from the visible filename.

---

## 6. Editor area

The editor region appears as:

```text
editor area (group) [DVTSplitView_ControlledBy_IDEEditorArea]
```

This points to `IDEEditorArea` as the controller responsible for the central workspace. The editor area contains further split views so Xcode can support:

- a primary editor;
- assistant or additional editor columns;
- tabbed editor contexts;
- a lower debug area;
- control bars and jump bars around editor content.

A representative hierarchy from the Asset Catalog capture is:

```text
editor area [DVTSplitView_ControlledBy_IDEEditorArea]
└── <empty> split group [IDEEditorSplitView_ControlledBy_...]
    └── Assets.xcassets group [IDEEditorAreaSplitContentView_ControlledBy_...]
        └── Assets.xcassets group [IDEEditorContextClipView_ControlledBy_...]
            └── <empty> split group [IDESafeAreaAwareSplitView]
                └── <empty> split group [DVTSplitView]
                    ├── asset source list
                    └── asset editor controls/content
```

### `IDEEditorSplitView`

This is likely the immediate container for one or more editor panes. The name aligns with Xcode's ability to split editors horizontally or vertically.

### `IDEEditorAreaSplitContentView`

This appears to represent the content assigned to a particular editor split. It likely hosts the editor context, including the selected document editor and related chrome.

### `IDEEditorContextClipView`

The term “editor context” suggests that Xcode models each open editor pane as a context object: selected document, navigation history, current editor type, cursor/selection state, and auxiliary controls. The clip view likely bounds or clips the currently installed editor view.

### `IDESafeAreaAwareSplitView`

This wrapper probably adjusts layout around editor chrome, titlebar integration, accessory bars, or other safe-area concerns. Its presence in a macOS application illustrates that newer AppKit window layouts can still need explicit safe-area handling.

---

## 7. Source editor and Debug Area

The Debug Area capture exposes:

```text
editor area [DVTSplitView_ControlledBy_IDEEditorArea]
└── Debug Area (group) [DVTReplacementView]
    └── <empty> split group [DVTSplitView]
        ├── <empty> scroll area [SourceEditorScrollView]
        │   ├── Console (text entry area)
        │   │   [SourceEditor.SourceEditorContentView]
        │   └── 1 (scroll bar) [DVTMarkedScroller]
        ├── <empty> group [DVTControlBar]
        ├── <empty> scroll area [DVTScrollView]
        ├── 406 (splitter) [NSSplitViewSplitter]
        ├── <empty> scroll area [SourceEditorScrollView]
        ├── <empty> scroll area [SourceEditorScrollView]
        └── <empty> group [DVTControlBar]
```

### Debug Area is dynamically installed

The outer class is `DVTReplacementView`. This name suggests a placeholder or swappable host used when the Debug Area is shown or hidden. Instead of hard-coding all debug content into the workspace, Xcode can replace the placeholder's child with the appropriate debug interface.

### The console reuses Source Editor infrastructure

The Console is backed by:

```text
SourceEditorScrollView
SourceEditor.SourceEditorContentView
```

This is significant. Xcode's debug console is not merely an `NSTextView`; it reuses the Source Editor subsystem. That likely provides:

- syntax-aware text rendering;
- selection and editing behavior;
- efficient layout for large text buffers;
- custom gutters or markers;
- shared scrolling behavior;
- command completion or token handling.

### `DVTMarkedScroller`

The scrollbar class suggests support for marks in the scroll track. In source-oriented surfaces these can represent search hits, diagnostics, changes, breakpoints, or other document positions.

### Split debug panes

The multiple `SourceEditorScrollView` and `DVTScrollView` nodes, separated by an `NSSplitViewSplitter`, are consistent with the Debug Area's combination of:

- variable/watch views;
- debug navigator-like panes;
- console output/input;
- optional additional panes or collapsed regions.

The accessibility tree does not identify every pane by semantic name, so exact mapping is uncertain.

---

## 8. Asset Catalog editor

The Asset Catalog editor demonstrates how a specialized document editor is inserted into the generic editor area.

### Asset source list

One capture shows:

```text
DVTSplitView
└── DVTScrollView
    └── Assets (outline) [IBCSourceListOutlineView]
        ├── outline row [NSOutlineRow]
        ├── outline row [NSOutlineRow]
        ├── column [NSTableColumn]
        └── Assets (outline) [IBCSourceListOutlineView]
```

`IBC` is historically associated with Interface Builder-related components. Here, `IBCSourceListOutlineView` is used for the catalog's asset list. This suggests that some Asset Catalog infrastructure belongs to, or shares components with, the Interface Builder family of Xcode frameworks.

### Asset editor toolbar/control bar

Another capture shows:

```text
DVTSplitView
└── DVTControlBar
    ├── search text field [DVTSearchFieldCell]
    │   └── filter button [NSSearchButtonCellProxy]
    ├── Add an image or other asset (menu button) [DVTImageButton]
    ├── Delete selected assets (button) [DVTImageButton]
    └── search text field [DVTSearchFieldCell]
```

This indicates a reusable private control layer:

- `DVTControlBar` provides a standard Xcode bar container;
- `DVTSearchFieldCell` provides Xcode-specific search-field behavior or styling;
- `DVTImageButton` provides icon buttons and menu buttons consistent with the IDE.

The Asset Catalog editor is therefore composed from generic DVT controls plus an editor-specific outline and content view.

### Inferred Asset Catalog composition

```text
Asset Catalog editor plug-in
├── Source-list pane
│   └── IBCSourceListOutlineView
├── Main asset canvas/editor
├── Control bars
│   ├── search/filter
│   ├── add asset
│   └── delete asset
└── optional inspector integration
```

---

## 9. SwiftUI inside Xcode

The screenshots contain two clear examples of SwiftUI embedded inside AppKit.

### Xcode intelligence/chat surface

Inside the navigator area:

```text
navigator
└── group [_TtGC7SwiftUI13NSHostingView...IDEIntellig...]
    └── scroll area [SwiftUI.HostingScrollView]
        └── list [SwiftUI.AccessibilityLazyLayoutNode]
            ├── text and hyperlinks
            ├── buttons
            ├── images
            ├── progress indicators
            └── generated-code/status content
```

The `_TtGC...NSHostingView...` name is a mangled Swift generic class. The important part is `SwiftUI.NSHostingView`: Xcode embeds a SwiftUI hierarchy into its AppKit navigator shell.

Observed SwiftUI accessibility types include:

- `SwiftUI.AccessibilityNode`;
- `SwiftUI.AccessibilityLazyLayoutNode`;
- `SwiftUI.HostingScrollView`;
- generated SwiftUI text-field cell classes;
- progress indicators, buttons, images, and text nodes.

The list contains chat-style content, build status, code references, controls such as Add/Remove, and progress indicators. This indicates that modern Xcode features can be implemented as self-contained SwiftUI feature surfaces without replacing the AppKit workspace architecture.

### Accessibility Inspector itself

The Accessibility Inspector screenshot shows:

```text
Accessibility Inspector (application) [XRCApplication]
└── dialog [NSPanel]
    └── group [SwiftUI NSHostingView ...]
        ├── scope (toggle button)
        ├── Element (text)
        ├── Source Editor, ...
        ├── Captions (toggle button)
        ├── Back (button)
        ├── Play (toggle button)
        ├── Forward (button)
        └── scroll area [SwiftUI.HostingScrollView]
```

Its panel chrome remains AppKit (`NSPanel`, `NSToolbarView`, standard window buttons), but its main content is SwiftUI. This reinforces the hybrid pattern:

```text
AppKit process/window shell
└── NSHostingView
    └── SwiftUI feature UI
```

`XRCApplication` likely belongs to an internal developer-tool framework used by Accessibility Inspector rather than Xcode proper.

---

## 10. How the SwiftUI Preview canvas is represented

The additional captures reveal an important difference between **macOS previews** and **iOS previews**. Although both appear to the user as an Xcode canvas, they are not represented the same way in the macOS view and accessibility hierarchies.

### 10.1 macOS preview: a real AppKit-hosted application window

The macOS preview appears as a separate application and window:

```text
Application (application) [SwiftUI.AppKitApplication]
└── Xcode Previews (standard window) [NSPreviewTargetWindow]
    ├── group [_TtGC7SwiftUI13NSHostingView...AnyView...]
    │   ├── Create New Presentation ... (button)
    │   ├── RECENT PRESENTATIONS (text)
    │   ├── Study Cards (image)
    │   ├── QuickSlides (text)
    │   ├── Open Presentation... (button)
    │   └── ...
    ├── close button [_NSThemeCloseWidgetCell]
    ├── zoom button [_NSThemeZoomWidgetCell]
    └── minimize button [_NSThemeWidgetCell]
```

A macOS SwiftUI preview is therefore not merely a bitmap drawn into Xcode. It is hosted as an actual AppKit application/window surface:

```text
SwiftUI.AppKitApplication
└── NSPreviewTargetWindow
    └── SwiftUI.NSHostingView
        └── real SwiftUI accessibility elements
```

The controls inside the preview remain individually visible to macOS accessibility. Buttons, text, images, scroll areas, and other SwiftUI nodes are inspectable as semantic UI elements. Window chrome is ordinary AppKit chrome.

> For a macOS target, the Xcode preview canvas is effectively a live native UI hosted in a special preview window, not a flattened screenshot.

The preview process/window is separate from the main `IDEApplication` workspace. Xcode coordinates it, but Accessibility Inspector sees it under `SwiftUI.AppKitApplication` and `NSPreviewTargetWindow`, rather than as descendants of `IDEWorkspaceWindow`.

### 10.2 iOS preview: a SimulatorKit display surface embedded in Xcode

The iOS preview capture has a different shape:

```text
IDEApplication
└── IDEWorkspaceWindow
    └── editor area
        └── IDEEditorContextClipView
            └── IDESafeAreaAwareSplitView
                └── SwiftUI.NSHostingView
                    └── SwiftUI.HostingScrollView
                        └── SimulatorKit.SimDisplayRenderable...
                            ├── Loading games... [AXPMapPlatformElement]
                            ├── Adventures (tab) [AXPMapPlatformElement]
                            ├── Library (tab) [AXPMapPlatformElement]
                            ├── Create Game (tab) [AXPMapPlatformElement]
                            ├── Settings (tab) [AXPMapPlatformElement]
                            ├── Action (button) [NSButtonCell]
                            ├── Volume Up (button) [NSButtonCell]
                            ├── Volume Down (button) [NSButtonCell]
                            └── Sleep/Wake (button) [NSButtonCell]
```

At the AppKit layout level, the simulated device content is represented primarily by a **single SimulatorKit display/renderable view**. Xcode does not instantiate the iOS application's UIKit or SwiftUI controls as native `NSView` objects inside the editor.

Instead, there are two layers:

```text
Xcode/AppKit host hierarchy
└── SimulatorKit display surface       one rendered device screen

Remote iOS accessibility bridge
└── AXPMapPlatformElement descendants  semantic elements from the guest UI
```

This explains the apparent contradiction in the capture:

- structurally, the canvas contains one simulated screen/render target;
- semantically, Accessibility Inspector may still show tabs, labels, and controls as `AXPMapPlatformElement` objects supplied through the simulator's cross-platform accessibility bridge;
- Mac-side simulator controls such as Action, Volume Up, Volume Down, and Sleep/Wake are ordinary AppKit controls, exposed as `NSButtonCell`.

Therefore, the iOS canvas is much closer to a remotely rendered screen than the macOS preview. Its application controls are not local AppKit widgets. They are pixels rendered by the simulator plus optional remote accessibility proxies.

### 10.3 Direct comparison

| Property | macOS SwiftUI preview | iOS SwiftUI preview |
|---|---|---|
| Top-level host | `SwiftUI.AppKitApplication` | Xcode's `IDEApplication` |
| Window/container | `NSPreviewTargetWindow` | Embedded editor/canvas hierarchy |
| UI rendering | Native AppKit/SwiftUI hosting | SimulatorKit-rendered device surface |
| App controls as local macOS views | Yes, through `NSHostingView` | No |
| Accessibility representation | Direct SwiftUI accessibility nodes | Remote `AXPMapPlatformElement` proxies |
| Window/device controls | Native AppKit window buttons | Native AppKit simulator buttons |
| Conceptual model | Live native preview application | Embedded remote screen plus bridge |

### 10.4 Implications for canvas implementation

This is a useful precedent for implementing a custom editor or presentation engine:

1. **A macOS preview can be a genuine secondary window/process.** The editor does not need to fake the application inside its own view tree. It can launch or host the real UI and coordinate it externally.
2. **A foreign-platform preview can be one render surface.** The host editor only needs a pixel/display surface, while input and accessibility are forwarded through a bridge.
3. **Visual hierarchy and semantic hierarchy can be separate.** One rendered screen can expose a large semantic accessibility tree without creating one native host view per guest control.
4. **Editor controls should remain outside the guest surface.** Device buttons and canvas controls can be ordinary host-platform controls while the preview remains isolated.
5. **Automation strategy differs by target.** A macOS preview can often be automated through normal native accessibility. An iOS preview requires simulator/XCUI accessibility or coordinate/input forwarding; traversing Xcode's `NSView` tree alone is insufficient.

The architecture can be summarized as:

```text
macOS preview
Xcode coordinator ── controls ──> real preview application/window

other-platform preview
Xcode editor ── hosts ──> rendered screen
             ── bridges ─> remote input/accessibility tree
```

---

## 11. Framework and class-prefix map

The captures allow a tentative subsystem map.

| Prefix/module | Likely responsibility | Examples observed |
|---|---|---|
| `IDE` / `IDEKit` | High-level IDE workspace, editor contexts, navigators | `IDEApplication`, `IDEWorkspaceWindow`, `IDENavigatorArea`, `IDEEditorArea`, `IDEEditorSplitView` |
| `DVT` | Shared Developer Tools UI and infrastructure | `DVTSplitView`, `DVTScrollView`, `DVTControlBar`, `DVTImageButton`, `DVTMarkedScroller` |
| `DVTExplorableKit` | Reusable hierarchical explorer UI | `DVTExplorerOutlineView` |
| `SourceEditor` | Source text layout/editing and console text surfaces | `SourceEditorScrollView`, `SourceEditorContentView` |
| `IBC` | Interface Builder / asset-catalog-related UI components | `IBCSourceListOutlineView` |
| `SwiftUI` | Newer embedded feature surfaces | `NSHostingView`, `HostingScrollView`, `AccessibilityNode` |
| `XR` / `XRC` | Accessibility Inspector or related developer tools | `XRCApplication` |
| AppKit (`NS...`) | Core windows, panels, split views, outlines, cells, toolbars | `NSSplitView`, `NSPanel`, `NSOutlineRow`, `NSTableColumn` |

This is an inference from runtime names; Apple does not document these private framework boundaries as supported APIs.

---

## 12. Probable internal architecture

A reasonable implementation model, based on the evidence, is:

```text
IDEApplication
├── global commands/services
├── workspace/document coordination
└── IDEWorkspaceWindow instances
    └── workspace window controller
        ├── IDENavigatorArea controller
        │   └── selected navigator implementation
        │       ├── Project navigator / DVT explorer
        │       └── Intelligence UI / SwiftUI hosting view
        │
        ├── IDEEditorArea controller
        │   └── IDEEditorSplitView
        │       └── one or more editor contexts
        │           ├── Source editor
        │           ├── Asset catalog editor
        │           └── other document editor plug-ins
        │
        ├── Debug Area host
        │   └── dynamically replaceable split-view content
        │       ├── variables/debug views
        │       └── SourceEditor-based console
        │
        └── Inspector/utilities area
            └── context-sensitive inspectors
```

### Likely model/controller concepts

Although not directly visible in the screenshots, the UI names imply several internal abstractions:

- **Workspace:** project/workspace state and document graph.
- **Area controller:** owns a stable region of the window.
- **Editor context:** navigation state and selected editor for one split.
- **Editor implementation:** feature-specific view/controller for a file type.
- **Navigator implementation:** one selectable navigation mode.
- **DVT shared controls:** IDE-wide visual and behavioral components.
- **Replacement/host views:** permit lazy insertion and removal of optional regions.

This separation would explain how Xcode can support dozens of file editors and navigators while retaining a consistent window shell.

---

## 13. Accessibility and automation implications

Apple documents that UI testing and inspection operate through the accessibility representation of the UI. `XCUIAutomation` can inspect UI state and control visible interface elements, while `XCUIElementSnapshot` represents element attributes and descendant hierarchy.

For Xcode automation, this has practical consequences:

1. Prefer stable semantic identifiers, labels, roles, and menu commands over private class names.
2. Treat private classes only as diagnostic hints.
3. Expect SwiftUI regions to expose virtual/lazy accessibility nodes.
4. Expect outline and table rows to be represented by accessibility proxy or mock elements.
5. Do not assume the accessibility parent/child relationship exactly matches `NSView.superview`.
6. Xcode updates can alter labels, hierarchy depth, class names, and implementation technology.

### What is probably automatable reliably

- opening menus and invoking named commands;
- selecting a known navigator by label;
- selecting visible project files by filename;
- focusing the editor or console by accessibility role/label;
- clicking clearly labelled Asset Catalog controls;
- reading visible build/status messages.

### What is likely fragile

- traversing by a fixed number of child indices;
- matching long private class names;
- depending on `<empty description>` wrapper nodes;
- assuming a specific number of split views;
- relying on generated SwiftUI mangled class names;
- trying to address off-screen virtualized rows without scrolling.

---

## 14. Design lessons for a lightweight Xcode alternative

The inspected architecture suggests several useful principles for an alternative IDE:

### Keep a stable shell and modular content

Define a small set of persistent regions:

```text
WorkspaceWindow
├── NavigatorHost
├── EditorHost
├── DebugHost
└── InspectorHost
```

Feature modules should provide content for those hosts instead of modifying the entire window.

### Model editor panes explicitly

An editor split should own an `EditorContext` containing:

- current document;
- editor type;
- navigation history;
- selection/cursor state;
- zoom and view state;
- optional assistant relationships.

This makes split editors and restoration straightforward.

### Build shared control primitives

Xcode repeatedly uses DVT-level controls and wrappers. A smaller IDE would benefit from equivalents such as:

- `IDEControlBar`;
- `IDESplitView`;
- `IDESearchField`;
- `IDEOutlineView`;
- `IDEMarkedScroller`;
- `EditorHostView`;
- `ReplaceablePane`.

### Reuse the text engine

Xcode appears to use Source Editor components for the debug console. A lightweight IDE can similarly reuse one text-engine abstraction for:

- source files;
- console;
- logs;
- diff views;
- search results previews;
- generated output.

The modes can differ while sharing layout, selection, tokenization, scrolling, and rendering.

### Permit mixed UI technology behind hosts

Xcode demonstrates that an AppKit shell can host newer SwiftUI modules. An alternative IDE could likewise keep a reliable native shell while allowing feature surfaces implemented in another declarative layer, provided the boundary is explicit.

### Accessibility should be part of the architecture

Semantic labels and roles make both assistive use and automation more reliable. An IDE intended for AI control should expose a stable semantic tree deliberately rather than relying on accidental view names.

---

## 15. Suggested architecture diagram for implementation

```text
Application
└── WorkspaceManager
    └── WorkspaceWindowController
        └── WorkspaceWindow
            └── RootSplitView
                ├── NavigatorAreaController
                │   └── NavigatorHostView
                │       └── NavigatorProvider
                │
                ├── EditorAreaController
                │   └── EditorSplitTree
                │       ├── EditorContextController
                │       │   └── EditorProvider
                │       └── EditorContextController
                │           └── EditorProvider
                │
                ├── DebugAreaController
                │   └── ReplaceableDebugHost
                │       ├── VariablesPane
                │       └── ConsoleEditor
                │
                └── InspectorAreaController
                    └── InspectorProvider
```

Suggested provider protocols:

```text
NavigatorProvider
- identifier
- title
- icon
- makeViewController(workspace)
- restoreState(...)

EditorProvider
- supportedDocumentTypes
- makeEditorContext(document)
- makeViewController(context)
- serializeViewState(...)

InspectorProvider
- supports(selection)
- makeInspector(selection)
```

This is not claimed to be Xcode's exact source-level design; it is an implementation-oriented abstraction consistent with the observed hierarchy.

---

## 16. Open questions for further inspection

The current screenshots do not expose enough information to answer these precisely:

- How the inspector/utilities area is represented internally.
- Whether editor providers use a formal plug-in protocol or internal extension-point registry.
- How tabs relate to `IDEEditorContext` and split views.
- Which object owns the jump bar and editor navigation history.
- Whether `DVTReplacementView` is a generic placeholder class used across Xcode.
- How the build system, indexer, debugger, and source-control models communicate with UI controllers.
- Whether the new intelligence surface is loaded from a separate framework or Xcode extension.
- Which portions of Source Editor remain AppKit views versus custom rendering layers.

Additional useful captures would include:

- workspace with the right inspector open;
- split editor with two files;
- source editor jump bar and minimap;
- debugger variables pane expanded;
- test navigator and report navigator;
- SwiftUI preview canvas;
- Interface Builder storyboard editor;
- window/view hierarchy from LLDB or a view debugger, for comparison with accessibility.

---

## 17. Public references

### Apple documentation

- [Xcode](https://developer.apple.com/xcode/) — Apple's overview of Xcode as the integrated toolchain for development, testing, debugging, profiling, and distribution.
- [Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector) — official entry point and documentation for the tool used to obtain these hierarchies.
- [Inspecting the accessibility of screens](https://developer.apple.com/documentation/accessibility/inspecting-the-accessibility-of-screens) — explains inspecting application UI through Accessibility Inspector.
- [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation) — Apple's UI automation framework, which operates against the accessible interface representation.
- [XCUIElementAttributes](https://developer.apple.com/documentation/xcuiautomation/xcuielementattributes) — includes snapshot concepts for element attributes and descendant UI hierarchy.
- [Archived: User Interface Testing](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html) — explicitly states that accessibility technology supplies the semantic UI data used by UI testing.

### Public evidence of private Xcode components

- [Xcode 12A7208 vs 12A7209 bundle diff](https://gist.github.com/rpendleton/c5e41605d3dd3bbfa43a70f2bf314f57) — lists resources inside private frameworks, including `IDEKit.framework`, `IDENavigatorArea.nib`, and `IDEWorkspaceWindow.nib`.
- [What is Xcode doing on the main thread?](https://gist.github.com/steipete/09ed94e78f084804a48291bef6c965c5) — a sampled Xcode process showing private IDE classes such as `IDENavigatorArea`, providing historical corroboration that these are real internal classes.

These non-Apple sources are observational and version-specific. They should not be treated as API documentation.

---

## 18. Concise class hierarchy inventory from the screenshots

```text
IDEApplication
└── IDEWorkspaceWindow
    └── NSSplitView (workspace root)
        ├── NSView_ControlledBy_IDENavigatorArea
        │   ├── DVTScrollView
        │   │   └── DVTExplorableKit.DVTExplorerOutlineView
        │   │       └── NSOutlineRow
        │   │           └── NSTableViewCellMockElement
        │   │               ├── text field
        │   │               └── DVTIconViewImageCell
        │   └── SwiftUI.NSHostingView
        │       └── SwiftUI.HostingScrollView
        │           └── SwiftUI.AccessibilityLazyLayoutNode
        │
        └── DVTSplitView_ControlledBy_IDEEditorArea
            ├── IDEEditorSplitView_ControlledBy_...
            │   └── IDEEditorAreaSplitContentView_ControlledBy_...
            │       └── IDEEditorContextClipView_ControlledBy_...
            │           └── IDESafeAreaAwareSplitView
            │               └── DVTSplitView
            │                   ├── DVTControlBar
            │                   │   ├── DVTSearchFieldCell
            │                   │   └── DVTImageButton
            │                   └── DVTScrollView
            │                       └── IBCSourceListOutlineView
            │
            └── DVTReplacementView (Debug Area)
                └── DVTSplitView
                    ├── SourceEditorScrollView
                    │   └── SourceEditor.SourceEditorContentView
                    ├── DVTMarkedScroller
                    ├── DVTControlBar
                    ├── DVTScrollView
                    └── NSSplitViewSplitter
```

---

## Conclusion

The accessibility captures reveal Xcode as a layered, modular native application:

- `IDEKit`-style objects define workspace-level concepts and persistent regions.
- `DVT` components supply common developer-tool controls and layout infrastructure.
- Specialized frameworks provide navigators and editors.
- Source Editor is reusable beyond source files, including the debug console.
- SwiftUI is embedded selectively inside a predominantly AppKit workspace shell.

For reverse engineering or for designing a smaller IDE, the most important pattern is the separation between **stable workspace areas**, **editor/navigator contexts**, and **replaceable feature implementations**. The private class names are useful evidence of that structure, but automation and new implementation work should depend on semantic abstractions rather than those exact names.
