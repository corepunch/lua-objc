# Diskmap

Disk cleanup for Mac developers that tells you what is safe
([VISION.md](VISION.md)). Diskmap does not scan the disk. It knows where
Xcode, the simulator, Git, the package managers, the editors, the AI tools
and macOS put the data developers lose space to, measures only those places,
and says for each item who owns it, what it is and whether it can go.

## Pages

- **Overview**: what can go now, the disk as one bar with a segment per
  source (the bar System Settings › Storage draws), and the sources ranked by
  size. *Remove Everything Safe…* removes every safe item after one
  confirmation that lists them.
- **Xcode**: DerivedData per project (a project that no longer exists is
  safe; the rest Xcode rebuilds on the next build), device support per OS
  version (the newest per platform is kept), archives oldest first (never
  safe: crash reports need them), Previews, documentation and other caches,
  device backups, the Command Line Tools.
- **Simulators**: devices and runtimes from `simctl`, with the measured
  device folders. A device whose runtime is gone, or a folder simctl no
  longer lists, is safe to delete; a stale device can be erased; a runtime
  no device uses is safe. Changes go through `simctl`.
- **Projects**: build folders found beside their markers in the folders
  people keep projects in (`~/Developer`, `code`, `Projects`, … and folders
  you add), with when each was last built and when its sources were last
  edited. A proven build folder idle for three months is safe; a build older
  than its sources says so.
- **Worktrees**: linked Git worktrees under the project folders and the
  tools' own worktree roots (`~/.codex/worktrees`, `.claude/worktrees`),
  classified from Git's own answers: ready (clean, published, idle),
  recent, changed, local commits, missing. Ready ones are removed with
  `git worktree remove`; missing registrations are pruned.
- **Packages**: download caches a lockfile restores (npm, pnpm, pip, uv,
  Homebrew, SwiftPM, CocoaPods, Cargo, Gradle, Maven, Go, …) and installed
  toolchains.
- **Editors**: caches Visual Studio Code, Cursor, Zed and JetBrains rebuild,
  and their extensions, where an older version beside a newer one is a
  leftover.
- **AI Tools**: Codex, Claude, OpenCode and Grok, folder by folder:
  transcripts are yours to decide about, caches and downloaded runtimes
  rebuild, local models are removed with their tool.
- **System Data**: what macOS Storage lumps together, taken apart: the
  other volumes by their own size (Preboot, swap, Recovery), the downloaded
  asset store (simulator runtimes, Siri, dictionaries, documentation), your
  caches and logs with each folder's owner, and temporary files. A cache no
  installed app claims is said to be exactly that.
- **Folder Map** (unlisted): any folder as one list, largest first, with what
  Diskmap knows about each item. Open it with *Look Inside* on any row, File ›
  Open Folder…, a folder dropped on the window or `--folder=<path>`.
- **Action History** (unlisted): every move, deletion and command Diskmap
  ran, from `~/Library/Logs/Diskmap/operations.log`.

Every row carries a verdict: *Safe to remove* (rebuilt or downloaded again
when needed), *Your decision* (history, downloads, work in progress), *In its
app* (cleared by its owner), *Managed by macOS*, or *Keep* (needed now, or
marked Keep). A verdict is a fact Diskmap computed or a dated line of its
dictionary, never a guess; the row's tooltip gives the reason.

## Removing

Nothing moves until you confirm. A row's trash button, its menu, *Remove
Safe Items…* on a page and *Remove Everything Safe…* on the Overview all
show one confirmation naming every item and what happens to it. Each item is
checked again just before it goes (`helpers/Verify.lua`): one whose app is
open, whose project file is gone, that was replaced, or whose simulator or
worktree state changed is skipped with its reason. Folders go to the Trash;
simulators through `simctl`; worktrees through `git worktree remove`
without force. The result is shown on the page and logged. The model is
updated without measuring again.

## Running

```sh
make
./lua-objc apps/diskmap/init.lua
./lua-objc apps/diskmap/init.lua --showcase            # the synthetic developer's Mac
./lua-objc apps/diskmap/init.lua --showcase --page=xcode --isolated
./lua-objc --screenshot=/tmp/overview.png apps/diskmap/init.lua --showcase
make diskmap-app
```

`--showcase` runs over `services/Fixture.lua`, a synthetic developer's Mac
described in `services/FixtureDisk.lua`: nothing is read from a real disk,
and every test runs against it. `--page=<location>` opens a page
(`--page=xcode`, `--page=/folder//Users/me`); `--isolated` shows it without
the sidebar; `--folder=<path>` opens the Folder Map.

## Layout

| Module | Owns |
| --- | --- |
| `knowledge/Locations.lua` | The dictionary: one dated line per folder with owner, sentence and verdict |
| `knowledge/Builds.lua` | Build folders by name, their project markers and inner proofs |
| `knowledge/Categories.lua` | The sources: the sidebar's pages |
| `knowledge/Library.lua`, `knowledge/Filesystem.lua` | What a folder in a Library is and whose, and the map of macOS locations (`helpers/Explain.lua`) |
| `knowledge/Paths.lua`, `helpers/Paths.lua` | The path guards: what may never be a cleanup target |
| `Store.lua`, `models/` | The store, `Items` (every measured row), `Categories` (the sources with their totals), `Keeps` |
| `services/Sources.lua` | One loader per source: what to ask the service, how to measure it, the verdicts |
| `services/System.lua`, `services/Fixture.lua`, `services/Contract.lua` | This Mac, the synthetic Mac, and the contract both keep |
| `services/Scanner.lua`, `src/plugins/storage/StorageScan.m` | The native bulk metadata scanner and command runner |
| `helpers/` | Pure computation over rows: Xcode, Simulators, Projects, Worktrees, Verdict, Verify, FolderTree, Format |
| `flows/Remove.lua`, `flows/Rows.lua`, `flows/Keep.lua` | Removing with confirmation and the last-second check; row presentation and menus; Keep |
| `pages/`, `routes.lua` | Overview, the `category` route the eight sources share, Folder Map, History |
| `views/` | etlua templates: the window, the sidebar, the pages, `components/ItemList.etlua` |
| `controllers/`, `Controller.lua` | The shell: environment, sidebar and history, menus, the window |

Headless tests (`tests/diskmap_*.test.lua`) cover the dictionary, every
source's verdicts over the synthetic Mac, every page, the remove flow with
its skips and log, the Folder Map, the guards and the history.
