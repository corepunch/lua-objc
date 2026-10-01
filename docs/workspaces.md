# Lightweight workspaces

Goal: a fresh source workspace (a linked Git worktree) adds **less than 100 MB**
of storage. Dependencies a task needs are measured separately, and build growth
stays visible. The limit does not cap iOS builds, simulator data or rendered
media, which are task outputs.

## What a workspace costs

| Part | Policy |
| --- | --- |
| Source checkout | Tracked files only, about 50 MB. `scripts/workspace-size.sh` measures it. |
| Git's record | `.git/worktrees/<id>`: a few hundred KB. History and objects stay shared with the main repository; never copy the repository to make a workspace, use `git worktree add`. |
| Submodules | Initialise only what the task needs, shallow: `git submodule update --init --depth 1 lua/vendor/etlua`. A Diskmap task does not need `apps/adventure-arena/zilscript` (about 41 MB); a task that does not touch the Git plugin does not need `vendor/libgit2` (about 61 MB). |
| Build output | `build/` is mutable and per worktree, so concurrent workspaces never share half-built files. |
| Compiled dependencies | Immutable, so they are cached once per pinned revision (see below) and cloned in. |

```sh
scripts/workspace-size.sh                              # source only
scripts/workspace-size.sh --submodules lua/vendor/etlua
LIMIT_MB=100 scripts/workspace-size.sh                 # nonzero above the limit
```

`tests/workspace_size.test.lua` fails when the tracked source passes the budget
or when the dependency cache is removed from the Makefile, so a space
regression shows up in `make test`.

## Dependency cache

`build/libgit2/<sdk>-<arch>/libgit2.a` is built from the pinned `vendor/libgit2`
revision with compiler inputs in `scripts/libgit2/`. The Makefile keys the
result by the source revision, those inputs, the SDK, the architecture and the
compiler version, stores it under `$(DEP_CACHE)/libgit2/<key>/` (default
`~/Library/Caches/lua-objc`), and copies it into `build/` with `cp -c`, an APFS
copy-on-write clone: the second and later workspaces use no extra space and
skip the compile. A changed revision or changed input gives a different key, so
a stale library is never reused.

## Reserve versus footprint

A desktop application's fixed free-space guard (a minimum free-space reserve
before it starts a task) is not part of a workspace's size, and shrinking this
repository does not remove it. Diskmap reports the bytes a worktree uses, never
the tool's reserve.
