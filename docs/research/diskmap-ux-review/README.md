# Diskmap UX review

Reviewed 5 October 2026 against `a16b27a3e586da28f0f562185db2852c622c6b01`.

Tracking issue: [Diskmap UX review 127](https://github.com/corepunch/lua-objc/issues/127).

Diskmap makes large storage categories easy to compare, but following an item from its size to its actual contents is less predictable. The strongest current finding is that Storage Map activation discards the selected location. Search scope and the transition from Developer projects to generated build data also interrupt the task of finding a specific space consumer.

This report evaluates the current flat radial charts. Criticism of the older installed version's extruded charts does not apply here.

## Evidence and limits

The current repository app bundle was built successfully using `make diskmap-app` with signing disabled for local review. The installed app previously inspected was an older build and is excluded from current findings.

**The live click walkthrough remains incomplete.** Computer Use repeatedly reported that the Mac was locked and automatic unlock failed. Manual unlock was requested. No successful live mouse or keyboard interactions with this current bundle were possible during this review.

Independent work completed while access was blocked:

- Mounted all 25 main manifest destinations using the current controller and synthetic showcase provider.
- Invoked the activation callbacks for all 56 Largest Locations rows and checked the resulting page or sheet and selected location.
- Invoked all 84 Large Files reveal callbacks with a stubbed Finder service. This verifies the dispatched path, not the Finder window that a real user would see.
- Exercised chart group and leaf activation, Overview category links, search persistence, page history, Folder Map directory and file activation, and File Types navigation.
- Inspected 11 native renders, including Storage Map at 950 × 580 in light appearance and 1400 × 900 in dark appearance.
- Ran five existing Diskmap test files outside the sandbox: **282 assertions passed**. The two files containing native drop helpers initially failed in the sandbox and subsequently passed outside it. Those initial failures are not reported as product defects.

Evidence labels used below:

| Label | Meaning |
| --- | --- |
| Handler verified | The app's current action callback was invoked and its resulting state inspected. Native hit testing and event delivery remain unverified. |
| Source verified | Current templates and route/model code establish the behavior. |
| Visual observation | A native render of synthetic showcase data was inspected. |
| UX inference | An assessment of likely user expectations, awaiting live task testing. |

The showcase disk is fictional. Sizes and counts below are fixture examples, not measurements of the user's Mac. Black selected sidebar rows in some offscreen captures are excluded from findings because the capture environment was locked.

## What works well

The flat Storage Map gives the chart enough space while keeping a compact ranked list alongside it. At the minimum supported window size, the chart, visible list rows, and Worth a look actions remain available. The list's names, amounts, and percentages provide a direct route to interpreting sectors without relying entirely on color. The dark render also preserves the chart's structure. These are visual observations, not measurements of target acquisition or accessibility.

Largest Locations is the strongest route for the question “what is taking space?” It ranks named locations across categories and includes parent context. All 56 tested activations reached a page or category sheet without a callback error; ordinary sheet destinations also selected the originating leaf.

Scope explanations are materially better in this build. Overview states measured and unattributed space; Storage Map states that shares use measured space; Developer tools explicitly explains overlap with Overview's Developer category. Different totals should therefore not be filed as an unexplained accounting bug.

Clean Up separates estimated recoverable bytes from locations requiring review. Projects names build data in its summary and protects dirty or unpushed work from bulk marking. Large Files visibly identifies the selected Yours filter and provides an All option. These choices support cleanup decisions, although some compete with the discovery task described below.

## Findings and priorities

### Storage Map loses the item being opened

**Priority P1. Handler and source verified.**

Reproduction: open Storage Map, enter Developer, and double-activate Developer projects. The resulting sheet is Developer with no selected leaf. Double-activating Xcode DerivedData similarly opens the Xcode category sheet without selecting DerivedData. Downloads opens Documents without selecting Downloads.

The same items from Largest Locations take different paths: Developer projects opens Projects, DerivedData opens the Xcode page, and Downloads opens Documents with Downloads selected. Storage Map's `drill` passes the parent ID to `app.open`; the normal location destination logic accepts the leaf ID and preserves its selection or dedicated route.

**UX impact:** a person has already identified a particular large item and must find it again. A category sheet also offers more choices than the selected item's dedicated page. This is the most concrete break in the discovery journey.

**Recommendation:** route leaf activation through the leaf's destination. If opening the parent sheet is intentional, select and scroll to the originating leaf and make the choice consistent with other entry points. Preserve the name, size, and location context on arrival.

Sources: [Explore.lua](../../../apps/diskmap/pages/Explore.lua), [Locations.lua](../../../apps/diskmap/models/Locations.lua), [Management.lua](../../../apps/diskmap/pages/sheets/Management.lua). Raw results: [activation.tsv](activation.tsv).

### Developer projects changes the population being inspected

**Priority P1. Handler and source verified; user confusion is a UX inference.**

The catalog describes Developer projects as “Source repositories and local build outputs” under `~/Developer`. Opening that resource from Largest Locations navigates to Projects. Projects lists only generated folders such as node_modules, target, and .build, grouped by project. Its fixture summary is 2.4 GB of build data in two projects.

The destination explains its own scope, but it does not continue the original question of which repository contents account for the selected location's size. Source files, datasets, assets, or other large folders are outside that list. The resource menu offers Finder and Quick Look but no direct Folder Map continuation.

**UX impact:** the route answers “which build outputs can I clean?” after the user asked “what is inside this large folder?” A clear destination heading helps once the user arrives but does not make that scope change predictable before activation.

**Recommendation:** offer separate, explicit actions such as Inspect Folder Contents and Review Build Data. Link the former directly to Folder Map for the resource's path. Name the latter according to its scope and show its build-data amount separately from the whole location's amount.

Sources: [Developer catalog](../../../apps/diskmap/catalog/Developer.lua), [Projects.lua](../../../apps/diskmap/pages/Projects.lua), [Rows.lua](../../../apps/diskmap/flows/Rows.lua).

### Search has a broad label and a narrow changing scope

**Priority P1. Handler and source verified; expectation of global search is a UX inference.**

The toolbar field says Search and has the accessibility label Search storage and guide. The query is shared across pages, while each page applies it to its own population.

Reproduction: search DerivedData in Largest Locations. One fixture location matches. Navigate to Large Files with the query still present: zero file rows match. Clearing Search restores the files. This is a correct local filter result, but the UI leaves the user to reconcile why something just found disappeared on the next page.

Storage Map adds another distinction: search filters the list while the chart retains the whole level so proportions stay true. Rectangles removes that list. Thus the same field can affect information outside the chart without narrowing the chart being viewed.

**Recommendation:** the simplest improvement is an explicit Search in this page label or scope indicator, clear search state on arrival, and visible explanations of the active query and filter in empty states. Decide whether queries persist per page or across navigation. If a cross-page search is desired, results need to name their destinations and preserve selection on arrival. Do not present a page filter as a search over the whole disk.

Sources: [Window.etlua](../../../apps/diskmap/views/layouts/Window.etlua), [Controller.lua](../../../apps/diskmap/Controller.lua), [Explore.lua](../../../apps/diskmap/pages/Explore.lua), [Files.lua](../../../apps/diskmap/pages/Files.lua).

### Large Files prioritizes reviewable files over the largest files

**Priority P2. Handler and visual verified; discoverability impact is a UX inference.**

The default Yours view contains 21 fixture files totaling 70.1 GB. All contains 84 files totaling 355.7 GB, including the largest fixture file, a 35 GB library image. The current banner makes Yours visible and the empty state suggests All, so this is not an invisible filter.

However, a person choosing Large Files to diagnose storage must notice the filter and choose All to see the actual largest ranked files. The prominent Mark Files action reinforces a cleanup task before the user has completed discovery.

**Recommendation:** consider All as the discovery default, retaining Yours as the reviewable subset. Alternatively state Show all 84 measured files beside the initial banner and distinguish measured files from files available for cleanup. Evaluate this with a task such as “find the largest individual file,” without prompting the tester about the filter.

Sources: [Files.lua](../../../apps/diskmap/pages/Files.lua), [files render](screenshots/files.jpg), [activation.tsv](activation.tsv).

### Back tracks pages rather than exploration steps

**Priority P2. Handler and source verified; proposed change is a UX inference.**

Reproduction: visit Large Files, then Storage Map, then drill Developer and Xcode. Toolbar Back returns to Large Files rather than Developer. Map focus stays at Xcode when the map is revisited. Navigation history stores page IDs; map levels are not recorded.

The toolbar tooltip says Show the previous page, and the chart center and breadcrumb offer Up. The current behavior is therefore intentional page history, not a failed Back callback. The remaining issue is whether users expect a browser-style Back button to undo their latest drill action.

**Recommendation:** test that expectation directly. Either include map focus and folder paths in navigation history or make Up a prominent explicit action beside Back. Back and Forward should have one predictable model across Storage Map, Folder Map, and page transitions.

Source: [NavigationController.lua](../../../apps/diskmap/controllers/NavigationController.lua).

### Activation requires learning several outcomes

**Priority P2. Handler, source, and visual verified; ease-of-use assessment is a UX inference.**

Single-clicking a chart group drills, while selecting its table row highlights it. Double-activating a folder drills into it, a Folder Map file requests Quick Look, and a Large Files row requests Finder reveal. Overview category legend buttons open management sheets, whereas corresponding wedges open Storage Map at the category. Each behavior has a plausible purpose, but the labels and guidance do not consistently predict the destination.

Storage Map's help text explains hovering and clicking groups, but does not explain leaf double-activation. Several ranked lists depend on native row activation and ellipsis menus. A new user may select an item and stop, or activate it expecting the same inspector used elsewhere.

**Recommendation:** show an explicit selected-item action with a concrete destination, such as Inspect Contents, Preview File, Show in Finder, or Review Xcode Data. Keep native row behavior, but make the next step available without knowing a double-click convention. Use destination-specific help for Overview wedges and category buttons.

Sources: [Folder.lua](../../../apps/diskmap/pages/Folder.lua), [ListRoute.lua](../../../apps/diskmap/pages/ListRoute.lua), [Overview.lua](../../../apps/diskmap/pages/Overview.lua), [ResourceList.etlua](../../../apps/diskmap/views/components/ResourceList.etlua).

### Several discovery routes compete at the first decision

**Priority P3. Visual and source verified; information architecture assessment is a UX inference.**

The sidebar separates Overview, Storage Map, Folder Map, Largest Locations, File Types, and cleanup-oriented pages. These routes are useful once understood, but a novice must distinguish whole-disk categories, catalog locations, an arbitrary folder tree, and individual files before choosing the right tool.

Overview puts recovery advice first, followed by the disk chart, unmeasured-space explanation, and categories. Its Largest items section appears later. For the requested discovery task, the shortest ranked path is comparatively less prominent.

**Recommendation:** expose Find Largest Locations and Inspect a Folder directly from Overview. Give Storage Map and Folder Map a one-sentence distinction near their entry points. Keep cleanup suggestions available while making the answer to “what is taking space?” an obvious first action.

## Task walkthrough

| Task | Current verified path | Assessment |
| --- | --- | --- |
| Find the largest known storage consumer | Largest Locations → first ranked location → sheet with originating leaf selected | Strong handler result; live click ease unverified. |
| Inspect a specific map leaf | Storage Map → group → leaf double-activation → parent sheet without selection | Loses the selected item; P1. |
| Find all content inside Developer projects | Largest Locations → Developer projects → Projects build folders | Changes scope; full folder exploration requires another route. |
| Find the largest individual file | Large Files → change Yours to All → first row → Finder reveal request | Works through handlers; default filter adds a discovery step. |
| Find DerivedData by name | Search Largest Locations → one match → Xcode | Useful locally; query persists on other pages. |
| Inspect Downloads | Open Folder for Downloads → seven ranked children → directory drill or file Quick Look request | Folder/file handler behavior is coherent. Picker, Quick Look UI, and native clicks still need live verification. |
| Browse a file kind | File Types → activate kind → Large Files with that kind and All filter | Preserves kind/filter context through the handler. |
| Return after drilling two map levels | Toolbar Back → previous page | Consistent with tooltip, potentially surprising during exploration. |

## Page coverage

All destinations below mounted successfully in the synthetic controller walkthrough. Mounting verifies that a page renders its route; it does not mean every control was clicked. Specialized pages have their own data structures, so a missing generic list count does not mean an empty page.

| Destination | Additional coverage |
| --- | --- |
| Overview | Native render; category button and wedge handlers compared. |
| Clean Up | Native render; existing cleanup and review tests. |
| Applications | Mount; destinations reached from ranked app locations; existing page tests. |
| Large Files | Native render; Yours and All; 84 reveal callbacks; persistent search. |
| Duplicates | Mount only; live duplicate-group actions pending. |
| Simulators | Mount; activation from Largest Locations; live device actions pending. |
| Worktrees | Mount only; live repository actions pending. |
| Projects | Native render; activation from Developer projects and generated-folder locations. |
| Storage Map | Native renders at minimum and large sizes, light and dark; group and leaf actions; search; history. |
| Folder Map | Native empty render; loaded Downloads handlers; directory drill and file previews; existing 67-assertion folder test. |
| Largest Locations | Native render; all 56 row activation callbacks. |
| File Types | Native render; kind-to-files handler with kind and All filter preserved. |
| Disks & Volumes | Mount; existing 14-assertion volumes test. |
| Updates & Snapshots | Mount; existing page tests. |
| Developer tools | Native render; scope explanation inspected; ranked locations route to management pages/sheets. |
| Xcode | Native render; activation from DerivedData, device support, and archives. |
| Music Production | Mount; fixture locations opened their category management sheets. |
| Video Production | Mount; fixture libraries and caches opened their category management sheets. |
| Photography | Mount only; live workflow controls pending. |
| Design | Mount only; live workflow controls pending. |
| 3D & Game Engines | Mount only; live workflow controls pending. |
| Games | Mount; game locations opened Games management sheets. |
| Storage Guide | Mount only; live topic navigation pending. |
| macOS Folders | Mount only; live topic and Finder navigation pending. |
| Diskmap Help | Mount only; live links and tour pending. |

## Remaining live review

After manual unlock, run the current built bundle and complete the mouse and keyboard portion:

1. Activate each sidebar destination and every visible non-destructive primary, row, chart, breadcrumb, and menu action. Record source item, expected destination, actual destination, and retained selection.
2. Repeat the eight tasks above without relying on source knowledge. Check how easily the correct entry point and next action are found.
3. Verify Return, Tab, Command-F, Command-Y, Back, Forward, native selection, chart hit targets, and accessibility descriptions. Check that actual Finder and owner apps reveal the intended item.
4. Exercise loaded, empty, filtered, loading, stopped, denied-access, and error states on the current bundle. Repeat important tasks at the minimum and large window sizes in light and dark appearance.
5. Inspect review and confirmation screens without deleting, moving, or clearing any real data.

No completion-time score or numerical ease-of-use rating is assigned because the live task walkthrough is blocked. The report's actionable findings remain grounded in current handler behavior and source.

## Reproduction evidence

- [Navigation walkthrough results](navigation.tsv). The PAGE count is the number of rows in generic `presented.lists`, not a universal count of page content.
- [Activation and task results](activation.tsv). The 84 Finder calls and Quick Look calls use service stubs against fixture paths.
- [Overview](screenshots/overview.jpg), [Largest Locations](screenshots/largest.jpg), [Projects](screenshots/projects.jpg), [Clean Up](screenshots/cleanup.jpg).
- [Storage Map at minimum size](screenshots/map-min.jpg), [Storage Map large in dark appearance](screenshots/map-large-dark.jpg), [Large Files](screenshots/files.jpg).
- [Developer tools](screenshots/developer.jpg), [Xcode](screenshots/xcode.jpg), [File Types](screenshots/kinds.jpg), [Folder Map empty state](screenshots/folder.jpg).

Native render command pattern:

```sh
./lua-objc --internal-screenshot=/tmp/diskmap-ux.png --width=950 --height=580 \
  apps/diskmap/init.lua --showcase --page=map
```

Regression command:

```sh
make test TEST_FILES='tests/diskmap_chart_pages.test.lua tests/diskmap_pages.test.lua tests/diskmap_data_pages.test.lua tests/diskmap_folder.test.lua tests/diskmap_volumes.test.lua'
```

Related product discussion: [issue 52](https://github.com/corepunch/lua-objc/issues/52).
