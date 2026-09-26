# Adventure Arena redesign notes

Why the app looks the way it does, the references behind it, and what should
come next. This covers the library (sized for 20–30 adventures) and the
reading/playing screen.

## References worth studying

| Reference | What to take from it |
| --- | --- |
| [Apple HIG: Collections](https://developer.apple.com/design/human-interface-guidelines/collections), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Searching](https://developer.apple.com/design/human-interface-guidelines/searching), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | Shelves, carousels, and search that feel native. |
| [WWDC25: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/) | Liquid Glass controls float above content. Content scrolls under the chrome. |
| App Store (Today, Arcade) and Apple Books (Book Store, reader themes) | Editorial storefronts, numbered charts, genre tiles, and paper/sepia/night reading. |
| [80 Days: building the perfect text adventure for mobile](https://www.gamedeveloper.com/business/-i-80-days-i-building-the-perfect-text-adventure-for-mobile) and [inkle on UI (VICE)](https://www.vice.com/en/article/the-makers-of-mobile-hit-80-days-on-the-importance-of-amazing-ui-852/) | Treat text as the game. Show choices that make sense now. Give prose room and rhythm. |
| [Frotz for iOS](https://apps.apple.com/app/frotz/id287653015) and [MacStories: Interactive Fiction in the iOS Age](https://www.macstories.net/stories/interactive-fiction-in-the-ios-age-a-text-based-love-story/) | Parser IF on phones works when the app completes words from the story's own vocabulary. |
| [Mobbin](https://mobbin.com) | Real app screens. Search "library", "chat", "reader". |
| [Practical Typography](https://practicaltypography.com) and [Refactoring UI](https://www.refactoringui.com) | Measure, hierarchy, and restraint. |

## Library: a storefront, not a grid

A single carousel stops working past about ten titles. The home screen now
has short, labeled bands, as on the App Store:

1. **Featured hero.** One full-bleed cover with its genre, rating, and
   difficulty.
2. **Shelves by collection** (`collection` in the catalog). Examples: "The
   Zork Trilogy", "Infocom Classics", "Arena Originals". Each carousel shows up
   to 10 book-proportioned (2:3) covers and has **See All**, which opens a
   wrapping grid. Catalog order sets shelf order, so editors control it without
   a second table.
3. **Top Rated.** A numbered chart of five.
4. **Browse by Genre.** Tinted tiles, one per genre, each using the color of
   its first game.
5. **Search tab** (trailing, as in iOS 26). Every query word must match. Title
   matches rank first. An empty query shows the genre tiles.

The detail page adds difficulty (Infocom's published levels:
Introductory/Standard/Advanced/Expert), a Play button in the game's own tint,
and a **More in …** shelf. That shelf is how people move sideways through 30
titles.

## Playing: a storybook with a chat composer

The transcript used to be one long label. It is now structured
(`Session:transcript()`):

- **Title page.** The game title in the game's own typeface and color, then the
  byline and synopsis.
- **Colophon.** The Infocom banner (copyright/release) is set small and
  centered, like a book's imprint page.
- **Chapters.** Entering a new room opens "CHAPTER IV" with the room name. The
  first letter is an **illuminated initial**: about 3.4× the body size, tinted,
  and set in a face that suits the world. The faces are OS-bundled: Snell
  Roundhand for Zork and Spellbreaker, Futura Condensed for Planetfall,
  Baskerville italic for horror, Didot for the Victorian mystery, and
  Chalkduster for Wondertown. `look` and failed moves stay plain narration, so
  chapters mark real progress.
- **Your commands** appear right-aligned in tinted bubbles, like sent messages.
  The story answers as ordinary prose, not bubbles, because prose reads better
  full-width.
- **Cover theme (the default).** The game's cover art, blurred by the system
  thick material, fills the page, as album art does behind lyrics in Music.
  This does the job of a WhatsApp-style wallpaper, but it is different for
  every game and needs no extra art. The solid System/White/Sepia/Black themes
  remain.

### Type-ahead suggestions

A row of Liquid Glass chips above the composer (`models/Suggestions.lua`):

- **Empty composer:** open exits, the best action for each visible object
  ("open mailbox"), look, and inventory. One tap plays the command.
- **First word:** "l" → look, lock, light, *take leaflet*. "t" → take, turn on,
  … and *examine table* when a table is in the room.
- **After a verb:** only the objects the story says accept that verb.
  `open ` → mailbox, door, not forest. Two-object verbs offer the joining word
  (`put coin ` → in, on, under). `go ` offers exits.
- Vocabulary comes from the engine's `room-items` route (visible objects, their
  verbs, and the contents of open containers). Objects seen earlier stay
  suggestible, so what you carry can still be completed.

## Framework changes this needed

- `Label`/`ns.Font` accept `fontName` (the OS-bundled face; falls back to the
  system `design`). Implemented in `src/uikit/platform.m` and
  `src/appkit/editor.m`.

## Next ideas, in priority order

1. **Continue Playing.** Autosave each game. Add a first shelf showing each
   game's current chapter and room. The empty "Ongoing" tab becomes this list.
2. **True wrap-around initials.** Text currently runs beside the initial in a
   hanging column. A native `DropCapText` using TextKit exclusion paths
   (`NSTextContainer.exclusionPaths`) would let the second and later lines wrap
   under the letter, as in print.
3. **Chapter index / atlas.** Tapping the title in the navigation bar lists the
   chapters (rooms) visited and jumps to them. Later, draw a map from the exits
   between rooms.
4. **Tappable nouns in prose.** Link the objects named in the text, as Heaven's
   Vault and 80 Days do. A tap offers that object's verbs as chips.
5. **Typographic covers** for games without art: tint plus title in the game's
   initial face. Adding a game then needs no illustrator.
6. **Moments.** Haptics and a brief glass toast on score changes. The toast
   shows the chapter count and score.
