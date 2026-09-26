# Adventure Arena redesign notes

Why the app looks the way it does, the references behind it, and what should
come next. The previous pass built the storefront and the structured
transcript; this pass turns the reading screen from a chat into a **book**,
replaces the muddy brown palette with jewel tones, adopts the iOS 26 tab bar
and Liquid Glass where the system puts it, and adds reading progress.

## References

| Reference | What we took from it |
| --- | --- |
| [WWDC25: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/), [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) | Glass is for the control layer floating above content, never for content itself. Controls group in one container and merge. |
| [MacRumors: How Liquid Glass is changing in iOS 27](https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/) | iOS 27 diffuses busy content under glass more strongly and applies scroll edge effects to standard bars automatically. We register each page's scroll view with the system instead of drawing our own fades. |
| [NN/g: Liquid Glass is cracked](https://www.nngroup.com/articles/liquid-glass/) | Never put text on glass over busy imagery, and keep controls where users expect them. The page stays opaque paper; only chrome is glass. |
| Apple Books (reader, *Themes & Settings*) | Page themes shown as pages (Paper, Original, Quiet, Night), New York for body text, size, leading, and justification. The running head is the chapter. |
| App Store (Today cards) | Full-bleed editorial cards in a snapping carousel, one per screen on iPhone. |
| Music (mini player), iOS 26 | The story in progress rides above the tab bar in a glass accessory and moves inline when the bar minimizes. |
| [80 Days (inkle)](https://www.gamedeveloper.com/business/-i-80-days-i-building-the-perfect-text-adventure-for-mobile) | The text is the game. The player's choices are woven into the prose, not shown as speech bubbles. |
| Print typography: drop caps, small capitals, fleurons | Chapter openers, stage directions in small capitals, and a title page with an epigraph. |

The X post the brief linked (Opus 5.5 and UI design) returned HTTP 402
behind X's paywall, so it could not be read.

## Reading: a book, not a chat

The old reader put your commands in tinted bubbles on the right, as a
messaging app does. It now reads as a book:

- **Title page.** The author in small capitals, the title in the story's own
  face and colour, a fleuron (❦), and the tagline as an italic epigraph. The
  Infocom banner follows as a colophon.
- **Chapters.** A new room opens "CHAPTER IV" in small capitals and the room
  name as a heading. The first paragraph begins with a **three-line drop cap**
  that the text wraps around. It uses real TextKit exclusion paths, not a
  side column.
- **Your commands** are stage directions: small capitals in the story's ink,
  inline in the column, with no bubble and no right alignment. VoiceOver reads
  them as "You: …".
- **Running head.** The navigation title is the book's title over "Chapter IV ·
  Kitchen".
- **Folio.** The status line sits under the page in small type: "Score 10 of
  350 · 4 moves". Planetfall shows "Time 4602", because its MOVES global is the
  ship's chronometer.
- **Pages.** Paper (warm off-white, near-black ink, the default) follows the
  system appearance. Original uses system colours, Quiet is soft grey, and
  Night is always dark, status bar included. The old blurred-cover backdrop is
  gone: text on a blurred image is exactly the legibility failure NN/g
  describes.
- **Themes & Settings.** Size, themes as page swatches, Serif/Sans/Rounded/
  Mono, Compact/Normal/Relaxed leading, and Justify (which also turns on
  hyphenation). The same options appear in the Settings tab with a sample page,
  and they are persisted.

### Glass where the system puts it

Everything that is not the story floats in one `GlassEffectContainer` at the
foot of the page: the quick-actions menu, the command field, and the
**compass**, which is now an SF Symbol (`location.north.fill`) inside the
glass bar. Suggestion chips above them are glass buttons that merge as they
slide. When the score changes, a glass capsule ("✦ +10 points") drops from the
top of the page with a success haptic and fades after 2.2 s. The whole page is
tinted with the story's ink, so the cursor, send button and compass ring take
its colour.

## Colour: jewel tones, no brown

Each story's `tint` is a saturated jewel tone taken from its cover, checked by
a test to carry white type at WCAG 4.5:1. Each also has a lighter `tintDark`
for ink on dark pages. The pair is used as one dynamic colour (`"#4338CA|#A5B4FC"`).

| Story | Tint | Dark-page ink |
| --- | --- | --- |
| Zork I | indigo `#4338CA` | `#A5B4FC` |
| Zork II | rose `#BE185D` | `#F9A8D4` |
| Zork III | royal blue `#1D4ED8` | `#93C5FD` |
| Planetfall | teal `#0E7490` | `#67E8F9` |
| Spellbreaker | violet `#6D28D9` | `#C4B5FD` |
| The Lurking Horror | crimson `#B91C1C` | `#FCA5A5` |
| Sanitarium | emerald `#047857` | `#6EE7B7` |
| The Last Toymaker's Apprentice | fuchsia `#A21CAF` | `#F0ABFC` |
| The Limehouse Killings | slate `#334155` | `#CBD5E1` |

## Library: storefront plus progress

- **Discover** opens with a snapping carousel of full-bleed featured cards
  (`containerRelativeWidth="1"`, `scrollTargetBehavior="viewAligned"`), each
  with a clear-glass **Read** capsule. **Continue Reading** follows once a story
  is in progress, then the shelves, Top Rated, and genre tiles, which now carry
  SF Symbols.
- The **Library** tab lists every story in progress: cover, chapter and room,
  a progress bar tinted to the story, the status line, and a menu with **Start
  Over** and **Remove from Library**.
- **Search** is iOS 26's separate search tab (`role="search"`).
- The **tab bar accessory** (`tabViewBottomAccessory`) shows the latest story.
  One tap resumes it at its last page. It hides while a book is open.
- **Detail** runs the cover under the navigation bar and shows an App Store
  fact strip (rating, difficulty, genre, year), the blurb as prose, review
  cards in a carousel, and a floating `glassProminent` button tinted to the
  story: **Start Reading**, or **Continue · Chapter IV · Kitchen** with a
  glass **Start Over** beside it.

### Autosave

Every command is saved. A save is the story's random seed plus its command
history (`models/SavedGames.lua`, `services/JsonDocument.lua`). Resuming
replays the commands against an engine seeded the same way
(`ZILRuntime.random`, a private Park–Miller generator), which rebuilds the
exact chapters and prose. It does not announce old points again. Opening a
book without playing it is not saved. Headless tests never touch the real
store.

## Framework features this added

Each has headless tests (see `tests/paragraph.test.lua`,
`tab_accessory.test.lua`, `scroll_target.test.lua`, `leaf_padding.test.lua`,
`dynamic_color.test.lua`):

- `Paragraph` (long-form prose): leading, justification, hyphenation, and
  ink-measured drop caps via TextKit exclusion paths, on both platforms.
- `smallCaps` on `Label` and `ns.Font` (OpenType `smcp`).
- `TabAccessory` (`tabViewBottomAccessory`) and `Tab role="search"` (`UISearchTab`).
  UIKit tabs now use the `UITab` API.
- `containerRelativeWidth` and `scrollTargetBehavior` for carousels. Horizontal
  shelves deliver touches immediately.
- Pages register their scroll view for iOS 26 scroll edge effects and
  large-title collapse.
- `tint` on `Button` and as a view modifier. `glassProminent` draws white type
  (and maps to the prominent push button on the Mac).
- `light|dark` colour pairs in every colour attribute.
- `Toggle onChange`, `Label accessibilityLabel`, and empty `systemImage` means
  none.
- `padding` on leaf views (SwiftUI `.padding` on any view).
- A page forced dark drives the status bar style.
- `_documentRead`, `_documentWrite` and `_jsonEncode` on AppKit (shared with
  UIKit in `src/shared/lua_documents.m`).

## Next ideas, in priority order

1. **Tappable nouns.** Link objects named in the prose. A tap offers that
   object's verbs as chips, as Heaven's Vault and 80 Days do.
2. **Chapter index and atlas.** Tapping the running head lists visited rooms
   and jumps to them. Later, draw the map from the exits.
3. **Typographic covers** for stories without art: tint plus title in the
   story's face.
4. **iPad two-page spread** in landscape, with the column capped at a
   comfortable measure.
