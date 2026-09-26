# Diskmap vision and research

What people struggle with when a Mac's disk fills up, what other storage tools
offer, and how each finding became a Diskmap feature, a catalog entry or a
guide topic. [DESIGN.md](DESIGN.md) holds the product rules;
[README.md](README.md) describes what ships. This file records *why*.

## How the research was done

The September 2026 pass searched for "what's eating my space" threads and
their answers: Reddit (r/mac, r/MacOS, r/macbookpro), Apple Developer Forums,
Apple Support Communities, Stack Exchange, the Jamf community, Adobe's forums,
Macworld and developer blogs. It also compared storage tools old and new:
Norton Utilities (DOS, Windows and Macintosh versions), CleanMyMac, DaisyDisk,
GrandPerspective, OmniDiskSweeper, Disk Inventory X, WinDirStat, AppCleaner
and macOS's own Storage settings.

A caveat on sources: reddit.com could not be fetched directly from the research
environment, and search engines returned few Reddit threads verbatim. The
recurring Reddit answers below are the ones that the forums, articles and the
Reddit results that did surface all repeat. Where a claim rests on a single
report, it says so. No quotations are invented; figures come from the linked
sources.

## What people struggle with

### 1. "System Data is 200 GB and I don't know why"

The most common complaint. System Data is macOS's catch-all for anything not in
a named Storage category, and Storage settings offers no breakdown or cleanup
button for it. Answers point, in order of frequency, to:

- **Local Time Machine snapshots** and purgeable space that macOS counts as
  used until it needs it. A restart often shrinks System Data.
- **Caches** in ~/Library/Caches, especially browsers, chat apps, Spotify and
  creative tools (Adobe's Media Cache and After Effects disk cache reached
  hundreds of gigabytes in Adobe forum reports).
- **Runaway logs.** One Apple Developer Forums case: a **304 GB log** in
  `/opt/homebrew/var/log` from a service started with `brew services`. Mail's
  Connection Doctor logging and a "50 GB log file" also appear in Jamf reports.
  These logs never rotate and can be invisible to space-accounting tools.
- **Developer data**: Xcode DerivedData, simulator devices and runtimes, iOS
  DeviceSupport, Docker's single virtual disk.
- **The Spotlight index** (`.Spotlight-V100`), reported at up to 500 GB when
  corrupted; the fix is rebuilding it through Spotlight's Privacy list.
- **Document versions** (`.DocumentRevisions-V100`), reported for Sketch and
  other apps that autosave large files.
- **/private/var/folders** growing with temporary files from crashed apps.
- **Photos diagnostics** files of nearly 4 GB each, and data from software
  people forgot (Garmin maps is a cited example).

→ Diskmap: the whole System Data category is split by owner. New catalog
entries for Homebrew service logs, browser and chat caches, Steam games. Guide
chapter **Common culprits** (runaway logs, Spotlight index, document versions).
The Overview's "Not attributed" slice is labeled honestly instead of guessed.

### 2. "What is safe to delete in ~/Library?"

People open Library, see gigabytes, and ask which folders they may remove.
The consistent answer: caches are rebuildable, Application Support and
Containers are not, and the owning app should do the cleanup. Suggested
safe targets: DerivedData, old iOS DeviceSupport versions, offline
documentation, old device backups in MobileSync.

→ Diskmap: every catalog entry states its policy (Rebuildable, Review,
Essential, System managed) and consequence. Only verified rebuildable caches
can be moved to the Trash, and only after confirmation. Clean Up separates
**Rebuildable** from **Needs review** and never sums them into one "safe"
number.

### 3. Developers: "Xcode is using 90 GB"

An Apple Developer Forums thread with that title and many blog posts list the
same folders: DerivedData (safe anytime), iOS DeviceSupport (delete versions you
no longer debug), DocumentationCache/Index (rebuilds), CoreSimulator Devices
(manage with Xcode or `simctl`, never Finder), and runtime images. Newer
reports add:

- `~/Library/Developer/CoreSimulator/Caches` — dyld caches, safe to clear.
- Xcode's SwiftUI **preview devices** — clear with
  `xcrun simctl --set previews delete all`, not Finder.
- watchOS DeviceSupport and iOS Device Logs.
- Package caches: npm, pnpm, Yarn, bun, pip, uv, Homebrew, CocoaPods, SwiftPM,
  Cargo, Gradle, Maven, Go modules and the Go build cache, Deno, Carthage,
  node-gyp.
- **Test-runner browsers**: Playwright keeps one Chromium/Firefox/WebKit build
  per version and never removes old ones (6–12 GB reported); Puppeteer,
  Cypress and Electron builders do the same.
- **Language toolchains**: nvm, rustup, pyenv and SDKMAN keep every version.
- **Virtual machines**: Docker, Colima, OrbStack, UTM, VMware Fusion,
  VirtualBox, Parallels, Podman.

→ Diskmap: the Developer page (Xcode & simulators, packages & toolchains,
projects & editors, containers & VMs, AI tools & models), the Simulators page,
owner-run cleanups (`npm cache clean`, `pip cache purge`,
`simctl --set previews delete all`), and catalog entries for every folder
above.

### 4. Local AI models, the 2026 newcomer

Blog posts and cleanup-tool issue trackers report **50–150 GB** on active
machine-learning Macs across Ollama (`~/.ollama/models`), LM Studio
(`~/.lmstudio/models`, older `~/.cache/lm-studio`) and the Hugging Face cache
(`~/.cache/huggingface`). None of these tools deletes models you stopped using.
AI coding agents (Codex, Claude Code, Cursor, OpenCode) accumulate sessions,
checkpoints and caches.

→ Diskmap: an **AI agents** category with coding tools separated into caches,
sessions and worktrees, and a **Local AI models** group with owner-specific
advice (`ollama rm`, `huggingface-cli delete-cache`). File Types has an
"AI models & datasets" kind (`.gguf`, `.safetensors`, `.ckpt`, …).

### 5. iPhone and iPad leftovers

- **Device backups** in `~/Library/Application Support/MobileSync/Backup`,
  often for phones the person no longer owns. Delete from Finder › Manage
  Backups.
- **Restore images** (`.ipsw`, 5–8 GB each) in
  `~/Library/iTunes/iPhone Software Updates` and `iPad Software Updates`,
  kept after the update finishes.

→ Diskmap: iOS Files category with both, the restore images as rebuildable
suggestions, and a guide topic.

### 6. Mail and Messages

Years of attachments add up. Messages' own setting (Keep messages: 1 year) and
Storage settings' "Review large attachments" are the recommended tools;
deleting attachment files in Finder breaks conversations. Mail keeps
copies of opened attachments in `Mail Downloads`, which Mail recreates.

→ Diskmap: Message attachments (review via settings) and Mail's opened
attachments (rebuildable) as separate entries.

### 7. "I deleted the app but its data is still there"

Dragging an app to the Trash leaves its Containers, Application Support,
Caches and preferences. People ask for AppCleaner-style uninstallers and a way
to find data from apps that are already gone.

→ Diskmap: the **Applications** page shows each app with the data folders it
owns (matched by bundle identifier), its version and last-opened date, and
**Possible leftovers**: identifier-named folders no installed app claims.
Installed apps come from Spotlight (`mdfind`) across the whole Mac, so an app
outside /Applications does not make its data look orphaned; Apple identifiers
are never listed.

### 8. "I forgot about that 40 GB file"

The classic advice: sort Downloads by size, look for old installers (`.dmg`,
`.pkg`), disk images (`.iso`), archives, screen recordings and exported videos,
and anything not opened in a year. Many threads recommend GrandPerspective,
OmniDiskSweeper or DaisyDisk just to find large files.

→ Diskmap: **Large Files** (ranked individual files, last used, filters for
Unused for a year / Installers & archives / Media) and **File Types**. Only
ordinary documents in your home folder can be moved to the Trash from there.

### 9. Trash and "deleting didn't free anything"

Moving to Trash frees nothing until it is emptied; local snapshots can keep
deleted files' blocks alive; purgeable space confuses free-space readings.

→ Diskmap: Trash category with reviewed Empty Trash; guide topics on Trash,
local snapshots, and free vs available vs purgeable space.

## What other tools offer

| Tool | Feature | Diskmap |
| --- | --- | --- |
| macOS Storage settings | Categories, Recommendations (Store in iCloud, Optimize Storage, Empty Trash Automatically, Reduce Clutter) | Same category names; recommendations are tied to measured locations and their owners |
| CleanMyMac | Large & Old Files | **Large Files** with "Unused for a year" |
| CleanMyMac, AppCleaner | Uninstaller with leftovers | **Applications** with data folders and possible leftovers; Diskmap never uninstalls apps itself |
| CleanMyMac | Space Lens (visual map) | Overview donut; File Types donut |
| DaisyDisk, GrandPerspective, Disk Inventory X | Sunburst / treemap of folders | Deliberately out of scope ([DESIGN.md](DESIGN.md)): Diskmap groups by owner, not folder |
| Disk Inventory X, WinDirStat | Size by file type/extension | **File Types** with top extensions |
| OmniDiskSweeper | Sorted folder sizes | **Largest Items** and per-location breakdowns |
| Norton Utilities | Space Wizard (disk space analysis) | Diskmap as a whole |
| Norton Utilities | Norton Disk Doctor, Disk Monitor, System Information | **Disks & Volumes**: SMART health, FileVault, sealed system volume, APFS volumes, mounted disks, shortcut to First Aid |
| Norton Utilities | Speed Disk (defragmenter) | Guide: SSDs never need defragmenting |
| Norton Utilities | WipeInfo / Wipe File | Guide: FileVault plus Erase All Content and Settings |
| Norton Utilities | UnErase, FileSaver, Volume Recover | Guide: Trash, Recently Deleted, Time Machine |
| Norton Utilities (Windows) | Duplicate File Finder | Not built: needs file contents, which Diskmap never reads |
| Norton Utilities (Windows) | Disk Cleaner | Clean Up page, restricted to verified rebuildable data |

## Principles that came out of the research

1. **Group by owner, not by folder.** Nobody asks "how big is
   ~/Library/Group Containers"; they ask "why is Docker so big".
2. **Rebuildable is not the same as reviewable.** Mixing them into one
   "reclaimable" number is how cleaners delete someone's databases.
3. **The owner cleans up.** Prefer `simctl`, `npm cache clean`, Docker's prune,
   Finder's Manage Backups and app settings over deleting folders.
4. **Say what you cannot see.** Snapshots, the Spotlight index and protected
   stores are explained, not guessed.
5. **Never read file contents.** Names, sizes and dates only; this rules out
   duplicate detection by content.
6. **Show the whole checklist.** Clean Up lists every known space hog that was
   checked and found fine, so absence of a suggestion is informative.

## Backlog

Ideas the research supports that this pass did not build:

- **Growth over time**: persisting per-category totals (never paths) to answer
  "what grew this week". Needs a decision to relax "no scan results are
  retained".
- **Purgeable space** from `NSURLVolumeAvailableCapacityForImportantUsageKey`
  on Disks & Volumes and the Overview.
- **Free-space alerts** from the background check (Norton Disk Monitor).
- **Photos and iCloud**: Recently Deleted and Optimize Storage status.
- **Login items and background apps**, which cleaners bundle alongside
  storage tools.
- **Row menus on UIKit** (`UIContextMenuConfiguration`) for the shared list.
- **Possible duplicates by name and size**, clearly labeled as unverified,
  if reading contents stays off-limits.

## Sources

Forums and articles:

- [Macworld — How to clear System Data on Mac](https://www.macworld.com/article/676493/how-to-delete-system-data-mac.html)
- [Apple Support — Free up storage space on Mac](https://support.apple.com/ht206996)
- [Apple Developer Forums — Xcode using 90 GB with ~/Library/Developer](https://developer.apple.com/forums/thread/812408)
- [Apple Developer Forums — macOS Sequoia system data is 200 GB](https://developer.apple.com/forums/thread/758416)
- [Apple Developer Forums — System uses ~300 GB](https://developer.apple.com/forums/thread/79609)
- [Apple Developer Forums — The Grand GB robbery: non-accessible space](https://developer.apple.com/forums/thread/714732)
- [Apple Developer Forums — Core Simulator cache consuming disk space](https://developer.apple.com/forums/thread/758703)
- [Apple Developer Forums — FYI: Xcode and disk space](https://developer.apple.com/forums/thread/773153)
- [Jamf Community — Start-up disk full](https://community.jamf.com/general-discussions-2/start-up-disk-full-1924)
- [Jamf Community — Disks running full outside user partitions](https://community.jamf.com/general-discussions-2/macbook-air-disks-running-full-outside-user-available-partitions-29292)
- [Jamf Community — Hidden system files taking up space](https://community.jamf.com/general-discussions-2/system-hidden-files-taking-up-large-quanitties-of-storage-space-20526)
- [Adobe Community — Is it safe to delete the hidden Library folder's contents?](https://community.adobe.com/t5/premiere-pro-discussions/is-it-safe-to-delete-content-of-the-hidden-library-folder-to-free-space-on-my-mac/m-p/14759580)
- [DEV Community — Spotlight using hundreds of GBs](https://dev.to/vvo/how-to-avoid-spotlight-using-hundreds-of-gbs-and-rebuild-its-index-4kki)
- [DEV Community — Audit macOS System Data before deleting developer caches](https://dev.to/ufebri/audit-macos-system-data-before-deleting-developer-caches-flb)
- [DEV Community — Clear Hugging Face, npm, conda and Docker caches](https://dev.to/riponcm/how-to-free-up-disk-space-as-a-developer-clear-hugging-face-npm-conda-and-docker-caches-3h21)
- [Local AI models eating your disk (2026)](https://1erkinyagci.github.io/maccleaner/blog/local-ai-models-disk-space-mac.html)
- [reclaim issue #13 — local AI model caches](https://github.com/mralaminahamed/reclaim/issues/13)
- [Playwright — Browsers](https://playwright.dev/docs/browsers)
- [BleepingSwift — Free up disk space used by Xcode](https://bleepingswift.com/blog/free-up-xcode-disk-space)
- [MacPaw — Delete iOS software updates from Mac](https://macpaw.com/how-to/delete-ios-software-updates-from-mac)
- [Help Desk Geek — What are IPSW files](https://helpdeskgeek.com/what-are-ipsw-files-and-should-you-delete-them/)

Tools:

- [Norton Utilities (Wikipedia)](https://en.wikipedia.org/wiki/Norton_Utilities)
- [Norton Utilities 4.0 for Mac (Route Fifty)](https://www.route-fifty.com/digital-government/1998/12/norton-utilities-40-brings-pc-safeguards-to-macs/290560/)
- [MacPaw — CleanMyMac vs DaisyDisk](https://macpaw.com/cleanmymac/cleanmymac-vs-daisydisk)
- [DaisyDisk alternatives: GrandPerspective, OmniDiskSweeper, CleanMyMac](https://blog.apps.deals/daisydisk-alternatives-mac)
- [DaisyDisk (Wikipedia)](https://en.wikipedia.org/wiki/DaisyDisk)
