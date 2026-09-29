# Diskmap motion and selection

Status: accepted product rules. September 29, 2026.
Companion to [DESIGN.md](DESIGN.md). Does not change accounting, cleanup policy,
or sidebar structure.

Source: review of Abraham John’s interaction-gallery thread
(https://x.com/abmankendrick/status/2104144119345893485) against Diskmap’s
AppKit surface and the `reels/diskmap` showreel.

## Decision

Those galleries are a motion-literacy feed, not a UI kit. Diskmap stays a
source-list macOS utility. Bottom sheets, tab bars, confetti, hero loops,
pinch gestures, and swipe-to-delete do not enter the app chrome.

The showreel (`reels/diskmap`) already owns springs, masked reveals, motion
blur, kinetic type, and camera shake. That language stays in the reel and in
App Store preview captures. In-app page changes remain instant; the Map's
change of level is the one navigation that moves (see the motion budget).

## One selection token

Hover, keyboard focus, and click must paint the same resource everywhere:

- sunburst wedge
- treemap cell
- Overview / File Types donut sector
- `ResourceList` row
- overview stat card

Rules:

1. Accent color is selection only. Category color stays muted; rebuildable
   data stays hatched. Do not invent a second hover chrome: the list paints
   its native selected row and the chart its highlighted sector
   (`Sectors.highlight`). Rows carry no `selected` field and marks no
   per-selection opacity.
2. Hover on a chart sector or map cell updates the inspector with the same
   payload a row click would: name, owner, size, share, status, actions.
3. Hovering a donut sector points at its row in the ranked list beside it
   without scrolling the page. On File Types a click keeps the kind: the
   headline and Top extensions follow it, and a second click opens its
   largest files. On the Overview a click opens the Map inside the category.
   The chart is never the only readout (see DESIGN.md).
4. Keyboard and pointer stay in lockstep on the Map page (existing type-to-filter
   and arrow navigation). No gesture that has no key equivalent.
5. Hover is Preview-style data magnification (path breadcrumb + share), not a
   glow, scale-up, or shadow lift.

Pie sectors brighten in place on hover
([corepunch/lua-objc#61](https://github.com/corepunch/lua-objc/pull/61)) on the
Overview, File Types and the Map. Do not replace it with a mobile-style pop.

`models/Selection.lua` holds the token's rules: which ids are resources
(free space, the residual and folded remainders are not), which row owns an
id, and which extensions belong to a kind.

## In-app motion budget

Allowed:

- Size figures spring onto the number once a measurement commits.
- Share bars fill once per committed figure, not on every 15-minute refresh.
- Disclosure triangles use the framework `transition`.
- Reduce Motion on: all of the above snap; no springs, no fills.

Not allowed in the window:

- Page-to-page camera moves, shake, motion blur, kinetic type.
- Staggered list entrances on sidebar navigation.
- Confetti or success bursts after Trash.

Looking inside a Map group, or going back out, moves the rings to the new
level in one animation transaction. Reduce Motion shows the new level at once
(`tests/diskmap_motion.test.lua`). Switching the map's style stays instant.

## Cleanup confirmation

The Marked sheet is the only place to borrow “delight” from those galleries,
and only as confirmation, not celebration.

- Consequence copy is visible before the confirm button works.
- Items move to Trash one by one. Each row commits, then the next starts.
- Copy is “Moved to Trash,” never “Freed” (DESIGN.md).
- Capacity figure on Overview pulses only after remeasure, not at click time.
- Empty Trash is a separate beat after the moves finish.

## Light and dark

`reels/diskmap/capture.lua` already captures every page in both appearances at
1280×800. Any new hover or selection treatment must read in both. If a
reference clip only works on a black marketing hero, do not ship it.

## Showreel only

Steal storyboard discipline from 60fps (start state, transition, end state,
easing written down) for `shots.lua` and the wall-and-dive shot. Do not import
Slack pinch, wallet-hero cycles, or bottom-sheet snap points into `apps/diskmap`.

## Implementation order

1. Done: shared selection token used by the Overview donut, File Types donut,
   Map and rows.
2. Done: File Types sector ↔ top-extensions list cross-highlight.
3. Done: Map change of level behind Reduce Motion.
4. Stat cards join the selection token.
5. Marked sheet sequential Trash + post-remeasure pulse on capacity.
6. Reel storyboard notes in `reels/diskmap` (separate change).
