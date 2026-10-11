# Diskmap vision

Diskmap is disk cleanup for Mac developers that tells you what is safe.

It is not another disk visualizer. Treemaps and ring charts are solved,
free and prettier elsewhere; nobody needs one more. Diskmap earns its place
by knowing what a folder is, who owns it and whether it can go, and by
never moving anything until the person says so.

## Who it is for

Developers. They have the problem (Xcode, simulators, worktrees and build
folders eat 60–100 GB), they understand the answer, and they pay for
tools. Everyone else is welcome; nobody else is the target.

## What the front page is

The front page leads with the sources developers lose space to, and with
the one number people google:

- Xcode: DerivedData, device support, archives, old caches
- Simulators: devices and runtimes, especially unavailable ones
- Worktrees: merged and orphaned Git worktrees
- Projects: stale build output (`node_modules`, `.build`, `target`, …)
- System Data: macOS's black hole, decomposed and explained

The storage maps (Storage Map, Folder Map, File Types, Largest Locations)
are supporting views reached from these, not the product. They stay
useful; they stop being the first screen.

## What it promises

1. **It says what things are.** A row is never a bare folder name and a
   size. It carries who owns it and what removing it means, in a few
   words, from `knowledge/`.
2. **It never lies about what it does not know.** An unknown folder shows
   its owner when one can be inferred, its size and when it was last
   written, and "Not part of macOS" — never a guess. "We don't know this
   one" is a first-class state, not a bug.
3. **Nothing moves until the person confirms.** Flag from anywhere; review
   on one page; one deliberate Move to Trash; each item checked again just
   before it moves; a history of what moved. Trust is the feature.
4. **Safe suggestions come from conventions and measurements**, not from
   hand-written knowledge of individual tools. "Old DerivedData",
   "unavailable runtime", "merged worktree" and "build folder newer than
   its sources" are facts Diskmap computes. They can lead the front page.

## The knowledge layer, and how not to drown in it

Most of what Diskmap knows is stable: where macOS, Xcode and the package
managers put things. Rules by folder *kind* (`Library.parents`) explain any
app that follows Apple's conventions without naming it, and they move once
a decade.

The long tail is the tools that ignore convention: `~/.codex`,
`~/.opencode`, `~/.cursor`, `~/.ollama`. These are worth knowing and they
move often. Rules for them:

- One table, small, dated: a line per folder with the version it was
  checked against. Twenty entries for the tools developers actually run,
  not two hundred.
- Infer the owner before the meaning. A running process, an installed
  bundle or a tool on `PATH` names the owner cheaply; owner, size and
  last-written answer most of the question.
- Per-tool knowledge never leads the front page. "Clear Codex sessions"
  is a liability the week after Codex moves them. It is a note in Folder
  Map, shown with the same honesty as everything else.

## What it is not

- Not a do-everything cleaner. Twenty sidebar pages is a liability, not a
  feature. Each page must earn its place against the five above.
- Not a visualizer. A chart is a supporting view of data a list already
  shows; it is never the reason to open the app.
- Not a black box. If Diskmap cannot say why something is safe, it does
  not call it safe.

## How to use this document

When a feature request arrives, ask: which of the five sources does it
serve, or which promise does it keep? If neither, it waits. When two
designs compete, the one that reads from a convention or a measurement
beats the one that reads from a table about a specific tool.
