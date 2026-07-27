# Xcode UI Architecture

> **Dual-source reference:** Part I documents the runtime accessibility hierarchy captured 25 July 2026 via Accessibility Inspector. Part II supplements with reverse-engineered class-dump headers from `IDEKit`, `DVTKit`, `IDEFoundation`, `IDESourceEditor`, and the Interface Builder frameworks (`IDEInterfaceBuilderCocoaIntegration`, `IBAutolayoutFoundation`, `IBFoundation`).
>
> **Important:** Most classes prefixed `IDE`, `DVT`, `IBC`, `SourceEditor`, and `XR` are private implementation details. They are useful for understanding Xcode and for exploratory automation, but they are not stable APIs and may change between Xcode releases.

---

# Part I — Accessibility Hierarchy Observations

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

### 2.1 Accessibility Inspector captures

The screenshots were produced by Accessibility Inspector. That means the trees describe the **accessibility hierarchy**, not necessarily the exact `NSView` ownership tree. Accessibility may:

- omit non-accessible implementation views;
- flatten wrapper views;
- expose virtual rows or lazy SwiftUI nodes not present as individual persistent views;
- use generated accessibility proxies;
- report role names such as "group" or "split group" that are semantic rather than exact AppKit types.

However, many entries include their runtime class names, making the captures unusually useful for architectural inference.

Captured files: `Screenshot 2026-07-25 at 18.26.01.png` through `Screenshot 2026-07-25 at 18.43.03.png` (9 files).

### 2.2 Class-dump header evidence

A second source of evidence comes from class-dump headers extracted from Xcode private frameworks. These headers expose the Objective-C method signatures, ivars, protocols, and class hierarchy — providing a **code-level view** that complements the accessibility-level view. These headers come from:
- `IDEKit` — window, tab, editor, navigator, inspector classes
- `DVTKit` — shared developer-tool views (`DVTSplitView`, `DVTReplacementView`, `DVTTabBarView`, `DVTChooserView`)
- `IDEFoundation` — project model (`IDEWorkspace`, `IDEContainerItem`)
- `IDESourceEditor` — source code editing UI
- `IDEInterfaceBuilderCocoaIntegration` — Interface Builder Cocoa editing
- `IBAutolayoutFoundation` — autolayout constraint engine
- `IBFoundation` — IB serialization utilities

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

**From headers:** `IDEWorkspaceWindow : DVTDualProxyWindow` (`IDEKit/IDEWorkspaceWindow.h`). `DVTDualProxyWindow` (`DVTKit/DVTDualProxyWindow.h`) is an `NSWindow` subclass supporting two represented URLs (primary/secondary) and a custom title view. `IDEWorkspaceWindow` overrides key-view loop recalculation, cursor rect interception, and window zoom/cascade behavior. Its controller is `IDEWorkspaceWindowController`, which manages tab creation, full-screen transitions, mini-debugging morphing, and the tab bar.

### The document object behind the window

**From headers:** `IDEWorkspaceDocument : NSDocument` (`IDEKit/IDEWorkspaceDocument.h`) is the `.xcworkspace` / `.xcodeproj` file on disk. It:
- Owns a single `IDEWorkspace` (the in-memory project model, see Part II)
- Creates and manages multiple `IDEWorkspaceWindowController` instances
- Persists editor state (open files, cursor positions, assistant editor splits)
- Implements `DVTTabbedWindowCreation` to let windows create tabs

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

**From headers** (`IDEWorkspaceTabController.h`): The workspace root is not just a bare split view — it is owned by `IDEWorkspaceTabController`, one per tab. Each tab controller's `loadView` constructs a three-pane layout:

```
IDEWorkspaceTabController.view
 └── DVTSplitView (_designAreaSplitView)          ← horizontal 3-pane
      ├── DVTReplacementView → IDENavigatorArea    ← left: navigator
      ├── DVTReplacementView → IDEEditorArea       ← center: editor
      └── DVTSplitView (_utilityAreaSplitView)     ← right: vertical sub-split
           ├── DVTReplacementView → IDEInspectorArea  ← top right
           └── DVTReplacementView → IDELibraryArea    ← bottom right
```

All areas are loaded lazily through `DVTReplacementView`, which swaps in the appropriate `DVTViewController` subclass by extension identifier.

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

**From headers** (`IDEKit/IDENavigatorArea.h`): `IDENavigatorArea` owns a `DVTChooserView` (_chooserView) — the segmented icon bar at the top of the left sidebar. Each `DVTChoice` in the chooser has an `image` (SF Symbol icon), `toolTip`, `identifier` (e.g. `"IDEStructureNavigator"`), and `representedObject` (the `DVTExtension` for that navigator). When the user clicks a tab, `selectionIndexes` changes → KVO triggers `IDENavigatorArea` to swap the `DVTReplacementView`'s child to the selected navigator. Navigator extensions are registered under point `"Xcode.IDEKit.Navigator"`.

Navigator tabs visible in different contexts:

| Identifier | Navigator | Icon |
|---|---|---|
| `IDEStructureNavigator` | Project files | Folder |
| `IDESymbolNavigator` | Symbols | Hierarchy |
| `IDEFindNavigator` | Find | Magnifying glass |
| `IDEIssueNavigator` | Issues | Warning triangle |
| `IDETestNavigator` | Tests | Diamond |
| `IDEDebugNavigator` | Debug | Debugger |
| `IDEBreakpointNavigator` | Breakpoints | Breakpoint |
| `IDELogNavigator` | Logs | Speech bubble |

### Navigator base class

`IDENavigator : IDEViewController` (`IDEKit/IDENavigator.h`) — the base for all navigators. Owns an `IDENavigableItemCoordinator`, a `rootNavigableItem`, and supports `NSPredicate` filtering. `IDEOutlineBasedNavigator` extends it for tree-based navigators, managing an `IDENavigatorOutlineView` with object/selected-object arrays.

### `DVTScrollView`

The project tree is wrapped in `DVTScrollView`, probably a Developer Tools (`DVT`) subclass of `NSScrollView` providing Xcode-wide behavior or styling.

### Navigable items — the universal selection model

**From headers** (`IDEKit/IDENavigableItem.h`): Every selectable thing in Xcode is wrapped in an `IDENavigableItem`. These form trees that serve both the navigator outline views and the jump bar. Each wraps a `representedObject` (the underlying model — file reference, symbol, issue, breakpoint, test, etc.), maintains `parentItem` / `childItems`, and is coordinated by an `IDENavigableItemCoordinator`. Each navigator and each editor context has its own coordinator, but all ultimately trace back to the workspace's model objects.

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

### Editor hierarchy from class-dump headers

**From headers** — the editor system is a multi-layer hierarchy:

```
IDEEditorArea (center pane owner)
 └── IDEEditorModeViewController (editor mode: standard/assistant/version/genius)
      ├── primaryEditorContext: IDEEditorContext
      └── (in assistant mode) IDEEditorMultipleContext
           └── NSSplitView of IDEEditorContext instances
```

**`IDEEditorArea`** (`IDEKit/IDEEditorArea.h`) manages an `int editorMode` (standard, assistant, version, genius), tracks `IDEEditorContext *lastActiveEditorContext` for Command-click navigation, owns the debugger split overlay, generates the `IDEWorkspaceTabControllerLayoutTree` for the Navigation HUD (Cmd-J), and caches default persistent representations per document type.

**`IDEEditorModeViewController`** (`IDEKit/IDEEditorModeViewController.h`) owns the current mode's `primaryEditorContext` and `selectedAlternateEditorContext`, routes `openEditorOpenSpecifier:` and `openEditorHistoryItem:` to the right context, and controls assistant operations (add/remove split, change layout).

**`IDEEditorMultipleContext`** (`IDEKit/IDEEditorMultipleContext.h`) is an `NSSplitView` container of multiple `IDEEditorContext` instances, used in assistant editor mode. Provides `splitEditorContext:`, `closeEditorContext:`, and `addEditorContext` operations.

**`IDEEditorContext`** (`IDEKit/IDEEditorContext.h`, 336 lines) — the central class wrapping:
- An `IDEEditor` (the content — source editor, IB canvas, plist editor, etc.)
- An `IDENavBar` (jump bar)
- An `IDEEditorHistoryController` (back/forward)
- A `DVTFindBar` (find & replace)
- A `DVTScopeBarsManager` (scope bar)
- An `IDEEditorSplittingController` (add/remove split buttons)
- An `IDEEditorStepperView` (sibling navigation)
- An `IDEEditorIssueMenuController` (issue mini-menu)

The `.navigableItem` property drives everything: when it changes, the context resolves the document extension, opens an `IDEEditorDocument`, installs the appropriate `IDEEditor` subclass, and updates nav bar and history. The context also implements swipe navigation between history items using Core Animation overlay layers.

**`IDEEditorCoordinate`** (`IDEKit/IDEEditorCoordinator.h`) is a **static routing class** with no instances. It decides *where* to open a document — new window, new tab, adjacent editor, or Navigation HUD prompt — based on `NSUserDefaults` preferences and the active layout tree.

**`IDEEditor`** (`IDEKit/IDEEditor.h`) is the base class for all content editors. Owns an `IDEEditorDocument`, a `DVTFindBar`, and references its owner `IDEEditorContext`. Concrete subclasses include `IDESourceCodeEditor`, `IDEComparisonEditor`, and editors from extension bundles (plist, RTF, model, Interface Builder).

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

This appears to represent the content assigned to a particular editor split. **From headers**, this is the view that an `IDEEditorContext` places inside the `DVTReplacementView` in the `IDEEditorMultipleContext` split view.

### `IDEEditorContextClipView`

The term "editor context" suggests that Xcode models each open editor pane as a context object: selected document, navigation history, current editor type, cursor/selection state, and auxiliary controls. The clip view likely bounds or clips the currently installed editor view.

### How file selection propagates (navigator → editor → inspector)

**From headers** — the full chain when a file is selected in the Project Navigator:

```
1. IDEStructureNavigator (NSOutlineView selection)
   → selectionDidChange

2. IDENavigator.currentSelectedItems
   → bound via output selection binding

3. IDEWorkspaceTabController.navigatorArea
   → currentNavigator navigates

4. IDEEditorCoordinator (static routing)
   → openEditorOpenSpecifier:forWorkspaceTabController:eventType:
   → decides target: this tab, new tab, new window, adjacent editor

5. IDEEditorContext (target context)
   → openEditorOpenSpecifier: → installs IDEEditor

6. IDEEditorContext._currentSelectedItemsChanged
   → selection propagates to workspace IDESelection

7. IDEUtilityArea (both Inspector and Library)
   → sliceExtensionsForNavigableItems:inCategory:withWorkspaceDocument:
   → matches selected navigable items to inspector categories

8. Inspector installs appropriate slices:
   → File Inspector, Quick Help, Identity, Attributes, etc.
```

### Editor history

**From headers** — `IDEEditorHistoryController` (`IDEKit/IDEEditorHistoryController.h`) manages back/forward navigation with `previousHistoryItems` and `nextHistoryItems` stacks. `IDEEditorHistoryStack` wraps past/present/future items in a serializable container. `IDEEditorHistoryItem` holds a navigable item + state dictionary (cursor position, scroll offset). `IDEEditorContents` wraps an array of stacks (one per editor context) for top-level state serialization.

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

**From headers:** `IDEEditorArea` owns an `_editorModeHostView` and a `_debuggerSplitView` — a vertical `DVTSplitView` below the editor content. The debugger split holds a `DVTReplacementView` for the `IDEDebugBar` (step/continue/pause toolbar) and another for the `IDEDebugArea` (variables + console). The debug area can be toggled by `showDebuggerArea:`.

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

### Source Code Editor — detailed implementation

**From headers** (`IDESourceEditor/IDESourceCodeEditor.h`, 298 lines):

`IDESourceCodeEditor : IDEEditor` is the main source code editor. Key views:

| View | Type | Role |
|---|---|---|
| `scrollView` | `NSScrollView` | Outer scroll |
| `textView` | `DVTSourceTextView` | Core text editing |
| `layoutManager` | `DVTLayoutManager` | Syntax coloring, folding, line numbers |
| `containerView` | `IDESourceCodeEditorContainerView` | Hosts editor + toolbar |
| `sidebarView` | `DVTTextSidebarView` | Gutter (line numbers, breakpoints, fold ribbons) |

Capabilities include:
- **Syntax coloring** via `syntaxColoringContext`
- **Expression analysis** — `selectedExpression`, `mouseOverExpression` (drives Quick Help and jump-to-definition)
- **Jump to definition** via `IDESourceCodeNavigationRequest` on a background `symbolLookupQueue`
- **Diagnostic display** — `IDESourceCodeEditorAnnotationProvider` renders inline error/warning annotations
- **Analyzer results** — `IDEAnalyzerResultsExplorer` for step-by-step traces
- **Blame** — `IDESourceCodeSingleLineBlameProvider` with SCM blame popover
- **Breakpoints** — gutter click → `_createFileBreakpointAtLocation:`
- **Single-file processing** — `compileCurrentFile`, `analyzeCurrentFile`, `preprocessCurrentFile`, `assembleCurrentFile`
- **Source code generation** — supports programmatic code insertion

**`IDESourceCodeDocument : IDEEditorDocument`** (`IDESourceEditor/IDESourceCodeDocument.h`) is the document model. Key properties: `textStorage` (DVTTextStorage), `language` (DVTSourceCodeLanguage), `diagnosticController` (IDEDiagnosticController), `sourceLandmarks` (top-level structure: classes, methods), `generatesContent`, `lineEndings`, `textEncoding`.

**Diagnostic pipeline** (`IDESourceEditor/IDEDiagnosticController.h`):

```
IDESourceCodeDocument (text changes)
 → IDEDiagnosticController.scheduleDiagnosticsGeneration
 → IDEClangDiagnosticController.diagnose
 → IDEDiagnosticGeneratorOperation (NSOperation, runs clang on background)
 → diagnosticItems posted to document
 → IDESourceCodeEditorAnnotationProvider
 → DVTSourceTextView (inline bubbles, gutter markers, scroll marks)
```

**Text completion** — three strategies extending `DVTTextCompletionStrategy`:
- `IDETextCompletionSourceModelStrategy` — class/method/property names from index
- `IDETextCompletionFrameworksStrategy` — headers from linked frameworks
- `IDETextCompletionHeadersInSearchPathStrategy` — headers from search paths

### `DVTMarkedScroller`

The scrollbar class suggests support for marks in the scroll track. In source-oriented surfaces these can represent search hits, diagnostics, changes, breakpoints, or other document positions.

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

### Asset editor toolbar

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

```text
Accessibility Inspector (application) [XRCApplication]
└── dialog [NSPanel]
    └── group [SwiftUI NSHostingView ...]
```

Its panel chrome remains AppKit (`NSPanel`, `NSToolbarView`, standard window buttons), but its main content is SwiftUI. This reinforces the hybrid pattern:

```text
AppKit process/window shell
└── NSHostingView
    └── SwiftUI feature UI
```

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

> For a macOS target, the Xcode preview canvas is effectively a live native UI hosted in a special preview window, not a flattened screenshot.

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
                            ├── ...
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

---

# Part II — Class Implementation Details

## 13. The Workspace Model (`IDEWorkspace`)

**From headers** (`IDEFoundation/IDEWorkspace.h`, 246 lines):

`IDEWorkspace : IDEXMLPackageContainer` is the in-memory representation of a project. Key owned subsystems:

| Property | Type | Role |
|---|---|---|
| `runContextManager` | `IDERunContextManager` | Schemes, targets, destinations |
| `logManager` | `IDELogManager` | Build & activity logs |
| `issueManager` | `IDEIssueManager` | Errors, warnings, analyzer |
| `breakpointManager` | `IDEBreakpointManager` | All breakpoints |
| `batchFindManager` | `IDEBatchFindManager` | Find-in-project |
| `testManager` | `IDETestManager` | Test suites & results |
| `index` | `IDEIndex` | Clang/LLVM code index |
| `refactoring` | `IDERefactoring` | Refactoring engine |
| `textIndex` | `IDETextIndex` | Full-text search index |
| `workspaceArena` | `IDEWorkspaceArena` | DerivedData layout |
| `executionEnvironment` | `IDEExecutionEnvironment` | Build settings env |
| `snapshotManager` | `IDEWorkspaceSnapshotManager` | Project snapshots |
| `sourceControlWorkspaceMonitor` | `IDESourceControlWorkspaceMonitor` | SCM status |
| `userSettings` / `sharedSettings` | Workspace settings | Per-user/per-team |

Tracks `referencedContainers` (subprojects, frameworks), `referencedBlueprints` (buildable targets), and `referencedTestables`. Supports `simpleFilesFocused` mode for untitled QuickLook-style workspaces.

---

## 14. Tab Bars — All Three Bar Types

Xcode uses **two distinct tab-bar widget classes** in three locations:

| Bar | Widget | Location | Controls |
|---|---|---|---|
| **Editor tab bar** | `DVTTabBarView` + `DVTTabSwitcher` | Top of editor area | File tabs: close, reorder, detach, new-tab, overflow |
| **Navigator tab bar** | `DVTChooserView` | Left sidebar top | Navigator icons: Project, Symbol, Find, Issues, etc. |
| **Utility tab bar** | `DVTChooserView` | Right sidebar (inspector + library) | Inspector categories + Library categories |

### 14.1 Editor tab bar — `DVTTabBarView` + `DVTTabSwitcher`

```
DVTTabSwitcher (NSView wrapping NSTabView + DVTTabBarView)
 ├── DVTTabBarView : DVTSlidingViewsBar : DVTBarBackground
 │    ├── DVTTabButton (one per open tab, title + close)
 │    ├── DVTNewTabButton (+ button at right edge)
 │    ├── DVTClippedTabsIndicator (overflow "»" menu)
 │    └── DVTSlidingAnimation (slide tabs for reorder)
 └── NSTabView (tabless — content switching via IDEWorkspaceTabController)
```

**`DVTTabBarView`** (`DVTKit/DVTTabBarView.h`):
- Drag-to-reorder tabs via `reorderSlidingView:fromMouseDownEvent:`
- Detach tab to new window via morphing drag image (`_detachTab:withClickPoint:sourceView:`)
- Overflow clipping with "»" menu when tabs don't fit
- Close buttons, new tab button, background theming (active/inactive × main/non-main)
- Drag-and-drop to accept tabs from other windows

**`DVTTabSwitcher`** (`DVTKit/DVTTabSwitcher.h`):
- Bridges `DVTTabBarView` to `NSTabView`
- `activeViewController` → current `IDEWorkspaceTabController`
- `selectTabViewItem:` → tells `IDEWorkspaceWindowController` to `activateWorkspaceTabController:`

**`DVTSlidingViewsBar`** (`DVTKit/DVTSlidingViewsBar.h`):
- Base class providing drag-reorder with `dropIndex`, `DVTSlidingAnimation`, `DVTClippedTabsIndicator`

### 14.2 Navigator tab bar — `DVTChooserView`

`DVTChooserView : DVTBorderedView` (`DVTKit/DVTChooserView.h`) renders a segmented-button bar using an `NSMatrix` of button cells. Each tab is a `DVTChoice`:

```objc
@interface DVTChoice : NSObject
@property NSString *title;
@property NSString *toolTip;
@property NSImage *image;
@property NSString *identifier;
@property id representedObject;  // the DVTExtension
@property BOOL enabled;
@end
```

Key properties: `choices` (array of DVTChoice), `selectionIndexes` (NSIndexSet), `allowsEmptySelection`, `choicesFillWidth`, `justification`, `gradientStyle`.

When a tab is clicked, `_chooserButtonClicked:` fires → `selectionIndexes` updates → `IDENavigatorArea` swaps the `DVTReplacementView`'s controller.

### 14.3 Utility tab bar — `DVTChooserView`

`IDEUtilityArea` (`IDEKit/IDEUtilityArea.h`) owns a `DVTChooserView` for category tabs. The utility area split (`_utilityAreaSplitView`) is a vertical `DVTSplitView` within `IDEWorkspaceTabController`:

```
DVTSplitView (_utilityAreaSplitView)
 ├── DVTReplacementView → IDEInspectorArea
 │    └── DVTChooserView (inspector categories: File, Quick Help, Identity...)
 │         └── DVTStackView_ML of DVTDisclosureView-wrapped slice content
 └── DVTReplacementView → IDELibraryArea
      └── DVTChooserView (library categories: Snippets, Objects, Media...)
           └── DVTStackView_ML of DVTDisclosureView-wrapped slice content
```

**Category resolution:** `IDEUtilityArea._rebuildCategoriesAndStack` gets the editor's navigable items, queries each `IDEInspectorCategoryController` for matching slices, builds `DVTChoice` objects for valid categories, and displays them in the chooser. When a category is selected, `_rebuildStackWithNavigableItems:` constructs the vertical `DVTStackView_ML` of `DVTDisclosureView`-wrapped inspector slice content views.

### 14.4 Tab bar state persistence

- Editor tab bar state (which files, order, selected tab) is persisted through `IDEWorkspaceDocument` (tracks `stateSavingRecentEditorDocumentURLs` and `stateSavingDefaultEditorStatesForURLs`) and `IDEWorkspaceWindowController` (tab controllers' state)
- Navigator chooser selection is persisted via `IDENavigatorArea.commitStateToDictionary:`
- Utility chooser selection is persisted via `IDEUtilityArea`'s `preferredCategoriesPersistenceKey`

---

## 15. Inspector Resolution Detail

### IDEInspectorArea and IDEUtilityArea

`IDEInspectorArea : IDEUtilityArea` (`IDEKit/IDEInspectorArea.h`) — the right-top pane:
- Overrides `sliceExtensionsForNavigableItems:` to match selected navigable items to inspector categories via `IDEInspectorCategoryController`
- Maintains a dictionary of `IDEInspectorCategoryController` instances per category
- Routes editor selection changes to appropriate inspector slices

`IDEUtilityArea : IDEViewController` (`IDEKit/IDEUtilityArea.h`) — the base class shared by inspector and library:
- Owns a `DVTChooserView` for category tab selection and a `DVTStackView_ML` for stacking slice content
- Owns its own `IDENavigableItemCoordinator` to observe workspace content
- Derives input selection from the workspace's `IDESelection`

### IDEInspectorViewController

`IDEInspectorViewController : IDEViewController` (`IDEKit/IDEInspectorViewController.h`) — one inspector slice:
- Holds `inspectedObjectsController` (NSArrayController — selected objects) and `inspectedDocumentsController` (selected documents)
- Content is XML-driven via `IDEBindableDeclarativeInspectorController` — the layout (rows, labels, controls) is defined in plists loaded from extension bundles
- Supports undo, issue display, and deferred reload

### IDEInspectorCategoryController

`IDEInspectorCategoryController : NSObject` (`IDEKit/IDEInspectorCategoryController.h`):
- Wraps a `DVTExtension` category and its inspector extensions
- `inspectorsForInspectedNavigables:withWorkspaceDocument:` determines which inspector slices apply to a given set of navigable items using type-matching and representation-matching strategies

### IDELibraryArea

`IDELibraryArea : IDEUtilityArea` (`IDEKit/IDELibraryArea.h`):
- Manages library content (Code Snippets, Object Library, Media Library, File Templates)
- Caches `previousLibraries` and `libraryExtensions`
- Supports collapse/expand and filter-field activation (`focusOnLibraryFilter`)

---

## 16. Interface Builder Pipeline

### 16.1 Framework stack

```
IDEInterfaceBuilderCocoa (plugin init, 3rd-party doc-archiving adapters)
        │
IDEInterfaceBuilderCocoaIntegration (Cocoa-specific editing layer)
  ├── IBCocoaDocument        (nib/xib document model)
  ├── IBCocoaAutolayoutEngine (runs NSISEngine offscreen)
  ├── IB*Editor classes      (view-specific editors)
  ├── IB*EditorCanvasFrame   (editor chrome)
  └── IBCocoa*Connection      (outlet, action, binding connections)
        │
IBAutolayoutFoundation (constraint engine, guides, frame deciders)
        │
IBFoundation (binary archiver, identity dict, message channel)
```

### 16.2 IBCocoaDocument

`IBCocoaDocument : IBDocument` (`IDEInterfaceBuilderCocoaIntegration/IBCocoaDocument.h`):
- Reads/writes `.xib` (XML) and compiles to `.nib` (binary keyed-objects format)
- Manages file owner, first responder, and application placeholder objects
- Runs 60+ verification methods for nib integrity
- Hosts an `IBCocoaAutolayoutEngine` that creates an offscreen `NSWindow` with a copy of the view hierarchy to run `NSISEngine` (AppKit's real constraint solver)

### 16.3 Editor hierarchy per view type

Every view class has its own `IBEditor` subclass:

```
IBEditor (abstract)
 ├── IBNSViewEditor (generic NSView)
 │    ├── IBNSTableViewEditor
 │    ├── IBNSSplitViewEditor
 │    ├── IBNSStackViewEditor
 │    ├── IBNSTabViewEditor
 │    ├── IBNSScrollViewEditor
 │    └── IBNSBoxEditor
 ├── IBNSWindowEditor  (window chrome, toolbar, simulation)
 ├── IBNSToolbarEditor (drag-to-configure toolbar)
 ├── IBNSMenuEditor / IBNSMenuItemEditor
 ├── IBNSCellEditor → per-cell subclasses (Button, TextField, Slider, etc.)
 └── IBTabViewItemEditor
```

Each editor supports **embedding policies** — wrapping views in containers via drag (e.g., embed in scroll view, split view, tab view, submenu).

### 16.4 Canvas rendering

**Window chrome:** `IBNSWindowEditorView` draws realistic window chrome (shadow, title bar, rounded corners, toolbar button) by mimicking a real `NSWindow` through custom drawing.

**Autolayout:** `IBCocoaAutolayoutEngine` installs copies of canvas views in an offscreen `NSWindow`, runs real `NSISEngine` for constraint solving, reads back frames, and updates the canvas. `IBAutolayoutArbiter` generates candidate constraints for ambiguous views and breaks mutually exclusive constraints. `IBAutolayoutFrameDecisionDriver` manages temporary sizing constraints during live resize.

**Layout guides:** `IBLayoutGuideGenerator` generates blue snap/drag guides (centering, edge, baseline, indentation) using `IBLayoutRuleManager`, which loads rules per widget type from plists.

### 16.5 Storyboards

The Mac `IBCocoaDocument` handles nib/xib. iOS storyboard support would extend the same `IBDocument` base with `UIStoryboard` integration via `UIStoryboardSegue`. The core `IDEInterfaceBuilder.framework` (containing `IBDocument`, `IBCanvas`, `IBStoryboard`) is not present in the DevKits dump — only the Cocoa plugin layer is available. Build pipeline: `.xib`/`.storyboard` → `ibtool` → `.nib`/`.storyboardc` (compiled binaries).

### 16.6 Nib serialization

- `IBBinaryArchiver` / `IBBinaryUnarchiver` — custom binary serialization with object ID tables
- `IBMutableIdentityDictionary` — `NSMapTable`-backed identity-based dictionary
- Connections (outlet, action, binding, accessibility) validate source/destination and archive to nib connector objects

---

## 17. State Restoration & Persistence

### 17.1 The DVTStatefulObject protocol

```objc
@protocol DVTStatefulObject
+ (long long)version;
+ (void)configureStateSavingObjectPersistenceByName:(id)arg1;
- (void)commitStateToDictionary:(id)arg1;
- (void)revertStateWithDictionary:(id)arg1;
- (void)setStateToken:(DVTStateToken *)token;
@end
```

Every major IDE object conforms to this. On quit: `IDEWorkspaceDocument.writeStateData` triggers a full state snapshot → each object's `commitStateToDictionary:` writes its state → serialized to `DerivedData/<workspace>-<hash>/` or `~/Library/Saved Application State/com.apple.dt.Xcode.savedState/`. On relaunch: `readStateData` → each object's `revertStateWithDictionary:` restores state.

### 17.2 DVTInvalidation

```objc
@protocol DVTInvalidation
- (void)primitiveInvalidate;
@optional
@property(readonly, getter=isValid) BOOL valid;
@end
```

Every IDE object conforms. `primitiveInvalidate` cleans up KVO, notifications, timers, and child objects. Prevented memory leaks when tabs/windows/documents close.

### 17.3 Editor layout tree

`IDEWorkspaceTabControllerLayoutTree` and `IDEWorkspaceTabControllerLayoutTreeNode` (`IDEKit/IDEWorkspaceTabControllerLayoutTree.h`) encode the editor split hierarchy for:
1. **State restoration** — which files were open in which editors
2. **Navigation HUD** — the Cmd-J overlay

Each `LayoutTreeNode` has `orientation`, `contentType`, `children` (array), and `documentArchivableRepresentation` (what file is shown).

---

## 18. Debugger Integration (deep dive)

### 18.1 Debug area classes

`IDEDebugArea : IDEViewController` → `IDESplitViewDebugArea` → `IDEDefaultDebugArea`:
- `IDESplitViewDebugArea` adds `NSSplitView` for variables + console split
- `IDEDefaultDebugArea` provides the standard layout
- `IDEConsoleArea` provides the LLDB console with find bar, scope bar, and input history

### 18.2 Mini-debugging mode

`IDEWorkspaceWindowController` (`IDEKit/IDEWorkspaceWindowController.h`):
- `inMiniDebuggingMode` — compact debugger overlay
- `_changeToMiniDebugging:` / `_morphToMedium:` / `_morphToCollapsed` / `_morphToNonCollapsed:` — resize transitions
- `_reSnapshotContentViewToNewFrame:` — snapshot-based morph animation

### 18.3 Debugging addition lifecycle

`IDEWorkspaceTabController` manages debug addition controllers:
- `debuggingAdditionUIControllersForLaunchSession:` — returns debugger-related controllers
- `addDebuggingAdditionUIControllerLifeCycleObserver:` / `remove...` — observer pattern
- `_createDebuggingAdditionUIControllersForLaunchSession:` — creates on debug start
- Notifies observers of invalidation/update

---

## 19. DVTKit Base Views

The core custom views Xcode builds on:

| Class | Role |
|---|---|
| `DVTSplitView : NSSplitView` | Universal split container with state saving, animation, custom dividers |
| `DVTReplacementView : DVTLayoutView_ML` | Lazy-loads `DVTViewController` by extension ID; forwards bindings |
| `DVTChooserView : DVTBorderedView` | Segmented/tab-style button bar (NSMatrix-based) |
| `DVTStackView_ML : DVTLayoutView_ML` | Manual-layout stack with direction, spacing, inset |
| `DVTTabBarView : DVTSlidingViewsBar` | Native tab bar with reorder, close, overflow |
| `DVTTabSwitcher : NSView` | Wraps NSTabView + DVTTabBarView |
| `DVTDualProxyWindow : NSWindow` | Window with primary/secondary URLs + custom title |
| `DVTViewController : NSViewController` | Base VC with DVTInvalidation, nib loading |
| `DVTScopeBarView` / `DVTScopeBarController` | Filter/scope bar |
| `DVTFindBar` / `DVTIncrementalFindBar` | Find-and-replace bars |
| `DVTDisclosureView` / `DVTDisclosureHeaderView` | Collapsible sections (used in inspector slices) |
| `DVTLibraryController` / `DVTLibraryAssetView` | Library panel |

---

## 20. File-Type to Editor Mapping

When a document is opened, `IDEEditorContext._defaultDocumentExtensionForNavigableItem:` determines the document extension, which determines the editor:

| File Type | Document Extension | Editor Class |
|---|---|---|
| `.h`, `.m`, `.swift`, `.c`, `.cpp` | Source code | `IDESourceCodeEditor` |
| `.xib`, `.nib` | Interface Builder Cocoa | `IBCocoaDocument` → IB editor |
| `.storyboard` | Interface Builder Cocoa Touch | IB editor (iOS variant) |
| `.plist`, `.xcent`, `.entitlements` | Property list | `IDEPropertyListEditor` |
| `.xcdatamodeld` | Core Data model | `IDEDataModelEditor` |
| `.rtf` | RTF | `IDERTFEditor` |
| `.pdf` | PDF | `IDEPDFViewer` |
| `.playground` | Playground | Playground editor |

---

## 21. Key Architectural Patterns

### 21.1 DVTReplacementView lazy loading
Every major area uses `DVTReplacementView` with a `controllerExtensionIdentifier`. Extensions register what area they fill; the view lazy-loads the controller on first use.

### 21.2 DVTInvalidation lifecycle
All IDE objects conform to `DVTInvalidation`. `primitiveInvalidate` cleans up everything — prevents leaks.

### 21.3 Navigable items as universal selection
Every selectable thing is an `IDENavigableItem`. Navigators produce them, editors consume them, inspectors react to them.

### 21.4 Extension-based architecture
Navigators, editors, inspectors, debuggers, and libraries are all extensions loaded via `DVTReplacementView` or `IDEUtilityArea` slice management.

### 21.5 Stateful object graph
The entire IDE window state is serialized through `DVTStatefulObject` into a dictionary tree and persisted to disk.

---

## 22. Combined Class Hierarchy from Headers and Accessibility

```
IDEApplication
└── IDEWorkspaceDocument (NSDocument)
    └── IDEWorkspaceWindowController (NSWindowController)    ← 0–N windows
        ├── DVTTabBarView (tab strip)
        ├── DVTTabSwitcher (tab model)
        └── IDEWorkspaceTabController (IDEViewController)    ← one per tab
            └── DVTSplitView (_designAreaSplitView)
                ├── DVTReplacementView → IDENavigatorArea
                │    ├── DVTChooserView (navigator icons: Project/Symbol/Find...)
                │    ├── IDENavigatorFilterControlBar (filter field)
                │    └── DVTReplacementView → IDENavigator subclass
                │         ├── IDEStructureNavigator (project tree)
                │         ├── IDESymbolNavigator (symbols)
                │         ├── IDEFindNavigator (search results)
                │         ├── IDEIssueNavigator (errors/warnings)
                │         ├── IDETestNavigator (tests)
                │         ├── IDEDebugNavigator (debug)
                │         ├── IDEBreakpointNavigator (breakpoints)
                │         └── IDELogNavigator (build logs)
                │
                ├── DVTReplacementView → IDEEditorArea
                │    ├── IDEEditorModeViewController (mode: std/assistant/version/genius)
                │    │    ├── IDEEditorMultipleContext (NSSplitView of editor panes)
                │    │    │    └── IDEEditorContext × N
                │    │    │         ├── IDENavBar (jump bar)
                │    │    │         ├── DVTScopeBarsManager (scope bar)
                │    │    │         ├── IDEEditorHistoryController (back/forward)
                │    │    │         ├── DVTFindBar (find & replace)
                │    │    │         ├── IDEEditorSplittingController (add/remove split)
                │    │    │         └── IDEEditor subclass
                │    │    │              ├── IDESourceCodeEditor (+ annotations, completion)
                │    │    │              ├── IDEComparisonEditor (diff/merge)
                │    │    │              ├── IB editor (Interface Builder)
                │    │    │              └── ... (plist, RTF, model, etc.)
                │    │    └── (or IDEEditorBasicMode — single context)
                │    └── DVTSplitView (_debuggerSplitView)
                │         ├── DVTReplacementView → IDEDebugBar (step/continue/pause)
                │         └── DVTReplacementView → IDEDebugArea
                │              └── IDESplitViewDebugArea → IDEDefaultDebugArea
                │                   ├── Variables view
                │                   └── IDEConsoleArea (SourceEditorScrollView-based)
                │
                └── DVTSplitView (_utilityAreaSplitView)
                     ├── DVTReplacementView → IDEInspectorArea
                     │    ├── DVTChooserView (inspector: File/QuickHelp/Identity...)
                     │    └── DVTStackView_ML of DVTDisclosureView slices
                     │         └── IDEInspectorViewController (per slice, XML-driven)
                     └── DVTReplacementView → IDELibraryArea
                          ├── DVTChooserView (library: Snippets/Objects/Media/FileTmpl)
                          └── DVTStackView_ML of DVTDisclosureView slices
```

---

## 23. Design lessons for a lightweight Xcode alternative

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

## 24. Suggested architecture diagram for implementation

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

## 25. Accessibility and automation implications

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

## 26. Open questions for further inspection

The current investigation does not resolve:

- How the inspector/utilities area is represented internally in the accessibility tree when expanded.
- Whether editor providers use a formal plug-in protocol or internal extension-point registry (likely the latter — `DVTReplacementView.controllerExtensionIdentifier`).
- How tabs relate to `IDEEditorContext` and split views (tabs = `IDEWorkspaceTabController`; editor panes = `IDEEditorContext`).
- Which object owns the jump bar and editor navigation history (`IDEEditorContext` owns the `IDENavBar` and `IDEEditorHistoryController`).
- Whether `DVTReplacementView` is a generic placeholder class used across Xcode (confirmed: every area uses it).
- How the build system, indexer, debugger, and source-control models communicate with UI controllers.
- Whether the new intelligence surface is loaded from a separate framework or Xcode extension.
- Which portions of Source Editor remain AppKit views versus custom rendering layers.

---

## 27. Public references

### Apple documentation

- [Xcode](https://developer.apple.com/xcode/)
- [Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector)
- [Inspecting the accessibility of screens](https://developer.apple.com/documentation/accessibility/inspecting-the-accessibility-of-screens)
- [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation)
- [XCUIElementAttributes](https://developer.apple.com/documentation/xcuiautomation/xcuielementattributes)

### Public evidence of private Xcode components

- [Xcode 12A7208 vs 12A7209 bundle diff](https://gist.github.com/rpendleton/c5e41605d3dd3bbfa43a70f2bf314f57) — lists resources inside private frameworks, including `IDEKit.framework`, `IDENavigatorArea.nib`, and `IDEWorkspaceWindow.nib`.
- [What is Xcode doing on the main thread?](https://gist.github.com/steipete/09ed94e78f084804a48291bef6c965c5) — sampled Xcode process showing private IDE classes such as `IDENavigatorArea`.

---

## 28. Concise class hierarchy inventory

```text
IDEApplication
└── IDEWorkspaceDocument (NSDocument)
    └── IDEWorkspaceWindowController (NSWindowController)     ← 0–N
        ├── DVTTabBarView + DVTTabSwitcher
        └── IDEWorkspaceTabController (IDEViewController)    ← 0–N tabs
            └── DVTSplitView (_designAreaSplitView)
                ├── NSView_ControlledBy_IDENavigatorArea
                │    ├── DVTChooserView (navigator icons)
                │    ├── DVTScrollView
                │    │   └── DVTExplorableKit.DVTExplorerOutlineView
                │    │       └── NSOutlineRow → NSTableViewCellMockElement
                │    │           ├── text field
                │    │           └── DVTIconViewImageCell
                │    └── SwiftUI.NSHostingView (intelligence/chat)
                │        └── SwiftUI.HostingScrollView → SwiftUI.AccessibilityLazyLayoutNode
                │
                ├── DVTSplitView_ControlledBy_IDEEditorArea
                │    ├── IDEEditorSplitView_ControlledBy_...
                │    │   └── IDEEditorAreaSplitContentView_ControlledBy_...
                │    │       └── IDEEditorContextClipView_ControlledBy_...
                │    │           └── IDESafeAreaAwareSplitView
                │    │               └── DVTSplitView
                │    │                   ├── DVTControlBar
                │    │                   │   ├── DVTSearchFieldCell
                │    │                   │   └── DVTImageButton
                │    │                   └── DVTScrollView
                │    │                       └── IBCSourceListOutlineView
                │    │
                │    └── DVTReplacementView (Debug Area)
                │        └── DVTSplitView
                │            ├── SourceEditorScrollView
                │            │   └── SourceEditor.SourceEditorContentView
                │            ├── DVTMarkedScroller
                │            ├── DVTControlBar
                │            ├── DVTScrollView
                │            └── NSSplitViewSplitter
                │
                └── Utility area (DVTSplitView)
                     ├── IDEInspectorArea + DVTChooserView
                     └── IDELibraryArea + DVTChooserView
```

---

## Conclusion

The combination of accessibility captures and class-dump headers reveals Xcode as a layered, modular native application built on a clear document-centered architecture:

- **`IDEWorkspaceDocument`** (NSDocument) owns the project workspace and creates windows.
- **`IDEWorkspaceWindowController`** (NSWindowController) manages the tab bar, tabs, and window-level state.
- **`IDEWorkspaceTabController`** (IDEViewController) is the heart of each tab, constructing a three-pane `DVTSplitView` (navigator | editor | utilities).
- **`IDEEditorArea`** manages the center pane with pluggable editor contexts, each wrapping a nav bar, jump bar, find bar, and the content editor itself.
- **`DVTReplacementView`** is the universal lazy-loading mechanism — every area (navigator, editor, debug, inspector, library) uses it.
- **`IDENavigableItem`** is the universal selection currency — navigators produce them, editors consume them, and inspectors react to them.
- **`DVTChooserView`** provides the tab bars on the left (navigators) and right (inspector/library categories).
- **`DVTTabBarView`** + **`DVTTabSwitcher`** provide the editor tab bar with drag-reorder, detach, and overflow.
- **`DVTStatefulObject`** serializes the entire IDE state for seamless restoration across launches.
- **`DVTInvalidation`** provides lifecycle cleanup across every object to prevent leaks.
- **Interface Builder** uses an offscreen `NSISEngine` for live autolayout, a hierarchy of per-view-type editors, and custom window chrome drawing for the canvas.
- **SwiftUI** is embedded selectively through `NSHostingView` in a predominantly AppKit workspace shell.
- **Previews** differ by platform: macOS previews are live native AppKit windows; iOS previews are embedded SimulatorKit-rendered surfaces with remote accessibility bridges.

For reverse engineering or for designing a smaller IDE, the most important pattern is the separation between **stable workspace areas**, **editor/navigator contexts**, and **replaceable feature implementations**.
