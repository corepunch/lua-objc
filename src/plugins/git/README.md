# Git native Lua plugin

`Git` is libgit2 (vendored at `vendor/libgit2`, a pinned submodule) exposed to
Lua. Apps use it instead of running a `git` executable through `io.popen`,
which iOS does not allow. On the Mac it is the standalone plugin
`build/Git.dylib`, found by `require("Git")` through `package.cpath`. The iOS
hosts (`make ios-host`, `scripts/ipad/build.mk`) link it statically and add it
to `package.preload`, so the same `require("Git")` works there.

`scripts/libgit2/libgit2.mk` builds `libgit2.a` directly with Apple Clang for
`macosx`, `iphoneos` or `iphonesimulator`; the project Makefiles call it. It uses
the system zlib, CommonCrypto and SecureTransport, so nothing else is vendored.
SSH, NTLM and GSSAPI are off. Run `git submodule update --init vendor/libgit2`
after cloning; building needs Xcode command-line tools and Make.

```lua
local Git = require("Git")
local repo = assert(Git.open(path) or Git.init(path))  -- init creates folders; branch "main"
repo:add()                                 -- like `git add --all`; takes a path or array of paths
local id = assert(repo:commit("Message", { name = "Ada", email = "ada@example.com" }))
for _, commit in ipairs(repo:log({ limit = 10 })) do print(commit.shortId, commit.summary) end
repo:close()                               -- also on __gc / __close
```

| Call | Result |
|---|---|
| `Git.version()` | libgit2 release, `"1.9.7"` |
| `Git.init(path [, {initialBranch}])` | repository |
| `Git.open(path)` | repository at a worktree or `.git` folder; parents are not searched |
| `repo:workdir()` | worktree path with a trailing `/` |
| `repo:head()` | `{branch, id, unborn, detached}` |
| `repo:status()` | `{path, index?, worktree?, oldPath?, conflicted?}` per changed path; `oldPath` on renames |
| `repo:files()` | tracked paths (`git ls-files`) |
| `repo:add([paths])` / `repo:unstage([paths])` | stage new, changed and deleted files (`git add --all`) / restore from HEAD (`git restore --staged`) |
| `repo:commit(message [, author])` | commit id; without an author, `user.name`/`user.email` |
| `repo:log([{limit, from}])` | `{id, shortId, summary, message, author, email, time}` newest first |
| `repo:branches()` | `{name, id, current}` |
| `repo:createBranch(name [, from])` / `repo:checkout(name)` | `true`; checkout is safe, never overwriting edits |
| `repo:diff([{staged}])` | unified patch text |
| `repo:show(revision, path)` | file bytes at a revision |

Repository failures return `nil, message`; wrong argument types raise errors.
Paths are a string or an array of strings; omitted, they match everything.
Options are an optional table.
Every call is synchronous and local — there is no clone, fetch or push yet.
Each call re-reads the index from disk, so separate handles to one repository
see each other's changes.
