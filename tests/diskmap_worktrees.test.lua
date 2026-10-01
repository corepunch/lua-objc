_G.__headless = true
local t = require("TestKit")
local Worktrees = require("apps.diskmap.models.Worktrees")
local Service = require("apps.diskmap.services.Worktrees")

-- Parsing `git worktree list --porcelain -z`.
local NUL = "\0"
local listing = table.concat({
	"worktree /r/main", "HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "branch refs/heads/main", "",
	"worktree /r/.claude/worktrees/feat", "HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "branch refs/heads/feat", "",
	"worktree /elsewhere/detached", "HEAD cccccccccccccccccccccccccccccccccccccccc", "detached", "locked in review", "",
	"worktree /gone/wt", "HEAD dddddddddddddddddddddddddddddddddddddddd", "branch refs/heads/old", "prunable gitdir file points to non-existent location", "",
}, NUL) .. NUL
local parsed = Worktrees.parse(listing)
t.assertEqual(#parsed, 4, "every worktree is parsed")
t.assertEqual(parsed[1].path, "/r/main", "paths are read as written")
t.expect(parsed[1].primary, "the first record is the primary checkout")
t.assertEqual(parsed[2].branch, "feat", "a branch loses its refs/heads prefix")
t.expect(parsed[3].detached and parsed[3].locked and parsed[3].lockReason == "in review", "detached and locked with its reason")
t.expect(parsed[4].prunable and parsed[4].pruneReason:find("non-existent", 1, true), "a missing registration is prunable")
t.assertEqual(#Worktrees.parse(""), 0, "an empty listing has no worktrees")
t.assertEqual(Worktrees.parse("worktree /a b\nc")[1].path, "/a b\nc", "paths with spaces and newlines survive the NUL format")

-- Managed locations.
t.assertEqual(Worktrees.manager("/Users/x/.codex/worktrees/3f2a/app"), "Codex", "Codex-managed worktrees are recognised")
t.assertEqual(Worktrees.manager("/Users/x/app/.claude/worktrees/feat"), "Claude", "repository-local Claude worktrees are recognised")
t.assertEqual(Worktrees.manager("/Users/x/custom/wt"), nil, "a custom location has no manager")

-- Overlapping listings count a worktree once.
local merged = Worktrees.merge({
	{commonDir = "/r/.git", entries = parsed},
	{commonDir = "/r/.git", entries = {parsed[2], parsed[1], parsed[3], parsed[4]}},
	{commonDir = "/other/.git", entries = {{path = "/r/main"}}},
})
t.assertEqual(#merged, 5, "the same repository listed from two checkouts adds nothing, another repository adds its own")
local primaries = 0
for _, entry in ipairs(merged) do if entry.primary then primaries = primaries + 1 end end
t.assertEqual(primaries, 2, "each repository has exactly one primary checkout")

-- Classification.
local NOW = 1800000000
local function classify(entry, facts, options)
	options = options or {}
	options.now = NOW
	return Worktrees.classify(entry, facts, options).state
end
local function entry(extra) local value = {path = "/r/wt", branch = "f"}; for k, v in pairs(extra or {}) do value[k] = v end return value end
local clean = {exists = true, changes = 0, untracked = 0, unpublished = 0, merged = true, submodules = 0, lastActivity = NOW - 30 * 86400, ignoredBytes = 0}
local function with(extra) local f = {}; for k, v in pairs(clean) do f[k] = v end; for k, v in pairs(extra) do if v == "nil" then f[k] = nil else f[k] = v end end; return f end
t.assertEqual(classify(entry(), clean), "candidate", "a clean, published, idle worktree is a candidate")
t.assertEqual(classify(entry({primary = true}), clean), "primary", "the primary checkout is never a candidate")
t.assertEqual(classify(entry({locked = true}), clean), "locked", "a locked worktree is protected")
t.assertEqual(classify(entry(), clean, {kept = true}), "kept", "Keep protects a worktree")
t.assertEqual(classify(entry({prunable = true}), clean), "missing", "a missing registration is a prune, not a removal")
t.assertEqual(classify(entry(), with({exists = false})), "missing", "a vanished directory is missing")
t.assertEqual(classify(entry(), with({changes = 2})), "dirty", "uncommitted changes block removal")
t.assertEqual(classify(entry(), with({untracked = 1})), "dirty", "untracked files block removal")
t.assertEqual(classify(entry(), with({unpublished = 3})), "unpublished", "commits no remote has block removal")
t.assertEqual(classify(entry(), with({merged = false})), "candidate", "published but unmerged work is still recoverable from its remote")
t.assertEqual(classify(entry(), with({merged = false})), "candidate", "and says so")
t.assertEqual(classify(entry(), with({submodules = 2})), "submodules", "initialized submodules need an explicit decision")
-- #100: "In use" means confirmed activity; a recent timestamp is only a recent change.
t.assertEqual(classify(entry(), with({lastActivity = NOW - 3600})), "recent", "a recently touched worktree waits for review")
t.assertEqual(classify(entry(), with({active = true})), "active", "a known running session protects it")
local recent = Worktrees.classify(entry(), with({lastActivity = NOW - 3600}), {now = NOW})
t.expect(not recent.eligible, "a recent change is never offered for removal")
t.expect(table.concat(recent.reasons, " "):find("cannot tell whether a session still uses it", 1, true), "and says what the evidence does not show: " .. table.concat(recent.reasons, " "))
t.assertEqual(Worktrees.roleNames.recent, "Recently touched", "it is labelled for what it is")
t.assertEqual(Worktrees.roleNames.active, "In use", "only confirmed activity reads In use")
local managed = Worktrees.classify({path = "/Users/me/.claude/worktrees/x", branch = "x"}, with({lastActivity = NOW - 3600}), {now = NOW})
t.expect(table.concat(managed.reasons, " "):find("archive the session in Claude", 1, true), "a held-back managed worktree explains its archive route: " .. table.concat(managed.reasons, " "))
t.assertEqual(classify(entry(), with({unpublished = "nil"})), "unknown", "an unreadable Git state is unknown, never clean")
t.assertEqual(classify(entry(), {}), "unknown", "no facts at all is unknown")
local unknownActivity = Worktrees.classify(entry(), with({lastActivity = "nil"}), {now = NOW})
t.assertEqual(unknownActivity.state, "candidate", "unknown activity alone does not block")
t.expect(table.concat(unknownActivity.reasons, " "):find("unknown", 1, true), "but it is stated, not assumed away: " .. table.concat(unknownActivity.reasons, " "))
local ignored = Worktrees.classify(entry(), with({ignoredBytes = 5e9}), {now = NOW})
t.expect(ignored.eligible and ignored.warnings[1]:find("ignored files", 1, true), "ignored data is a warning that goes with the removal")
t.expect(Worktrees.classify(entry(), with({changes = 1, unpublished = 2}), {now = NOW}).reasons[2], "every reason is listed")

-- Rows and the plan: storage is split and shared history is not counted per worktree.
local entries = {
	{path = "/r/main", primary = true, branch = "main", repository = "/r/main"},
	{path = "/r/.claude/worktrees/a", branch = "a", repository = "/r/main"},
	{path = "/r/.claude/worktrees/b", branch = "b", repository = "/r/main"},
	{path = "/r/.claude/worktrees/c", branch = "c", repository = "/r/main", locked = true},
	{path = "/r/.claude/worktrees/d", branch = "d", repository = "/r/main"},
	{path = "/r/.claude/worktrees/e", branch = "e", repository = "/r/main", prunable = true},
}
local facts = {
	["/r/main"] = with({bytes = 900e6, gitBytes = 0}),
	["/r/.claude/worktrees/a"] = with({bytes = 400e6, gitBytes = 20e6, generatedBytes = 250e6, ignoredBytes = 250e6}),
	["/r/.claude/worktrees/b"] = with({bytes = 100e6, gitBytes = 5e6, changes = 4}),
	["/r/.claude/worktrees/c"] = with({bytes = 50e6, gitBytes = 1e6}),
	["/r/.claude/worktrees/d"] = with({bytes = 60e6, gitBytes = 40e6, generatedBytes = 10e6}),
}
local rows = Worktrees.rows(entries, facts, {now = NOW})
local byName = {}
for _, row in ipairs(rows) do byName[row.name] = row end
t.expect(byName.a.eligible and byName.d.eligible, "clean linked worktrees are eligible")
t.assertEqual(byName.a.sourceBytes, 150e6, "source is the checkout without its generated output")
t.assertEqual(byName.a.generatedBytes, 250e6, "generated output is its own figure")
t.assertEqual(byName.a.gitBytes, 20e6, "Git's per-worktree record is its own figure")
t.assertEqual(byName.a.bytes, 420e6, "a worktree's bytes are its directory plus its own Git record, not the shared database")
t.assertEqual(byName.a.manager, "Claude", "managed worktrees name their manager")
t.assertEqual(byName.main.state, "primary", "the primary is listed but protected")
t.assertEqual(byName.e.state, "missing", "a missing registration is listed")
t.assertEqual(byName.e.size, "Not measured", "an unmeasured worktree is not zero")
local plan = Worktrees.plan(rows)
t.assertEqual(#plan.removal, 2, "two worktrees are in the removal set")
t.assertEqual(plan.removalBytes, 420e6 + 100e6, "the removal total adds each worktree once")
t.assertEqual(plan.sourceBytes + plan.generatedBytes + plan.gitBytes, plan.removalBytes, "source, generated and Git storage add up to the removal total")
t.assertEqual(#plan.review, 1, "a dirty worktree needs review")
t.assertEqual(plan.reviewBytes, 105e6, "review bytes are apart from removal bytes")
t.assertEqual(#plan.prune, 1, "a missing registration is a separate prune review")
t.assertEqual(#plan.protected, 2, "primary and locked are protected")
t.expect(plan.ready, "a plan with a removal set is ready")
t.expect(not Worktrees.plan({}).ready, "an empty plan is not")
t.assertEqual(Worktrees.removeCommand(byName.a)[4], "worktree", "removal is git worktree remove")
t.assertEqual(Worktrees.removeCommand(byName.a)[#Worktrees.removeCommand(byName.a)], "/r/.claude/worktrees/a", "for exactly that path")
for _, argument in ipairs(Worktrees.removeCommand(byName.a)) do t.expect(argument ~= "--force" and argument ~= "-f", "removal is never forced") end
t.assertEqual(Worktrees.removeCommand(byName.b), nil, "a dirty worktree has no removal command")
t.assertEqual(Worktrees.removeCommand(byName.main), nil, "neither does the primary")
t.assertEqual(Worktrees.pruneCommand(byName.e)[5], "prune", "a missing registration has a prune command")
t.assertEqual(Worktrees.pruneCommand(byName.a), nil, "an existing checkout is never pruned")
local ok, why = Worktrees.revalidate(byName.a, entries[2], with({changes = 1}), {now = NOW})
t.expect(not ok and why.code == "dirty", "a worktree that became dirty is refused at the last moment")
t.expect(not Worktrees.revalidate(byName.a, nil, clean), "a worktree Git no longer lists is refused")
t.expect(Worktrees.revalidate(byName.a, entries[2], facts["/r/.claude/worktrees/a"], {now = NOW}), "a still-clean worktree passes")
local text = Worktrees.confirmation(plan)
t.expect(text:find("Remove 2 worktrees", 1, true) and text:find("Claude keep their own session lists", 1, true), "the confirmation lists the set and names the owning app")

-- Real Git: linked worktrees, custom paths, overlapping roots, submodules, ignored and untracked
-- files, unpublished commits, locks, missing registrations. Removal leaves the rest usable.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/diskmap-worktrees.XXXXXXXX"))
local tmp = pipe:read("*l"); pipe:close()
tmp = tmp:gsub("^/private", "")
local ENV = "GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_ALLOW_PROTOCOL=file "
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function run(argv, done)
	local parts = {}
	for _, value in ipairs(argv) do table.insert(parts, quote(value)) end
	local command = "env " .. ENV .. table.concat(parts, " ") .. " 2>&1"
	local handle = io.popen(command)
	local output = handle:read("*a")
	local ok = handle:close()
	done(ok == true, output)
end
local function sh(command)
	local ok, output
	run({"/bin/sh", "-c", command}, function(a, b) ok, output = a, b end)
	assert(ok, command .. "\n" .. tostring(output))
	return output
end
local function measure(paths, done)
	local sizes = {}
	for index, path in ipairs(paths) do
		local handle = io.popen("/usr/bin/du -sk " .. quote(path) .. " 2>/dev/null")
		sizes[index] = (tonumber(handle:read("*a"):match("^(%d+)")) or 0) * 1024
		handle:close()
	end
	done(sizes)
end
local G = "/usr/bin/git -c protocol.file.allow=always "
sh("mkdir -p " .. tmp .. "/home/.codex/worktrees/abcd && cd " .. tmp .. " && " .. G .. "init -q --bare origin.git && " .. G .. "init -q -b main lib && cd lib && echo l > l.txt && "
	.. G .. "add . && " .. G .. "commit -qm lib")
sh("cd " .. tmp .. " && " .. G .. "clone -q origin.git proj 2>&1; cd proj && " .. G .. "checkout -q -b main 2>&1 || true; echo one > a.txt && "
	.. G .. "add a.txt && " .. G .. "commit -qm one && " .. G .. "submodule add -q " .. tmp .. "/lib lib 2>&1 && " .. G .. "commit -qm sub && " .. G .. "push -q origin main 2>&1 && "
	.. G .. "remote set-head origin main 2>&1 || true")
local P = tmp .. "/proj"
local function worktree(name, path, extra)
	sh("cd " .. P .. " && " .. G .. "worktree add -q " .. (extra or "") .. " " .. path .. " 2>&1")
end
worktree("clean", tmp .. "/custom/clean", "-b clean")
worktree("published", tmp .. "/custom/published", "-b published")
sh("cd " .. tmp .. "/custom/published && echo p > p.txt && " .. G .. "add p.txt && " .. G .. "commit -qm p && " .. G .. "push -q origin published 2>&1")
worktree("dirty", P .. "/.claude/worktrees/dirty", "-b dirty")
sh("cd " .. P .. "/.claude/worktrees/dirty && echo change >> a.txt")
worktree("untracked", tmp .. "/custom/untracked", "-b untracked")
sh("cd " .. tmp .. "/custom/untracked && echo u > u.txt")
worktree("unpublished", P .. "/.claude/worktrees/unpublished", "-b unpublished")
sh("cd " .. P .. "/.claude/worktrees/unpublished && echo n > n.txt && " .. G .. "add n.txt && " .. G .. "commit -qm n")
worktree("detached", tmp .. "/custom/detached", "--detach")
sh("cd " .. tmp .. "/custom/detached && echo d > d.txt && " .. G .. "add d.txt && " .. G .. "commit -qm d")
worktree("locked", tmp .. "/custom/locked", "-b locked")
sh("cd " .. P .. " && " .. G .. "worktree lock --reason review " .. tmp .. "/custom/locked")
worktree("codex", tmp .. "/home/.codex/worktrees/abcd/codex", "-b codex")
worktree("ignored", P .. "/.claude/worktrees/ignored", "-b ignored")
sh("cd " .. P .. "/.claude/worktrees/ignored && mkdir out && head -c 300000 /dev/zero > out/blob && echo out/ >> $(" .. G .. "rev-parse --git-path info/exclude)")
worktree("subs", tmp .. "/custom/subs", "-b subs")
sh("cd " .. tmp .. "/custom/subs && " .. G .. "submodule update --init -q 2>&1")
worktree("gone", tmp .. "/custom/gone", "-b gone")
sh("rm -rf " .. tmp .. "/custom/gone")

local repos
Service.repositories(run, {tmp, P}, function(found) repos = found end)
t.assertEqual(#repos, 2, "overlapping roots find each repository once; submodule repositories are not repositories to review: " .. #repos)
local project
for _, repo in ipairs(repos) do if repo.commonDir:match("/proj/%.git$") then project = repo end end
t.expect(project ~= nil, "the repository is discovered by its .git")
local entriesFound
Service.list(run, {project}, function(value) entriesFound = value end)
local names = {}
for _, row in ipairs(entriesFound) do names[(row.path:match("([^/]+)$"))] = row end
for _, expected in ipairs({"proj", "clean", "published", "dirty", "untracked", "unpublished", "detached", "locked", "codex", "ignored", "subs", "gone"}) do
	t.expect(names[expected], "git lists the " .. expected .. " worktree")
end
t.assertEqual(#entriesFound, 12, "custom paths, repository-local and Codex worktrees are all listed, once each")
t.expect(names.gone.prunable, "a deleted directory is a prunable registration")
t.expect(names.locked.locked, "a locked worktree is reported locked")

local factsByPath = {}
for _, row in ipairs(entriesFound) do
	Service.facts(run, measure, row, function(value) factsByPath[row.path] = value end)
end
local function fact(name) return factsByPath[names[name].path] end
t.assertEqual(fact("clean").changes, 0, "a clean worktree has no changes")
t.assertEqual(fact("clean").unpublished, 0, "and nothing unpublished")
t.expect(fact("clean").merged, "a branch at main is merged")
t.assertEqual(fact("dirty").changes, 1, "a modified tracked file is counted")
t.assertEqual(fact("untracked").untracked, 1, "an untracked file is counted")
t.assertEqual(fact("unpublished").unpublished, 1, "a local-only commit is counted")
t.assertEqual(fact("published").unpublished, 0, "a pushed branch has nothing unpublished")
t.assertEqual(fact("published").merged, false, "a pushed branch not in main is unmerged but published")
t.assertEqual(fact("detached").unpublished, 1, "a detached HEAD's own commit is at risk")
t.assertEqual(fact("subs").submodules, 1, "an initialized submodule is counted")
t.assertEqual(fact("clean").submodules, 0, "a worktree without initialized submodules has none")
t.expect((fact("ignored").ignoredBytes or 0) >= 200000, "ignored files are measured: " .. tostring(fact("ignored").ignoredBytes))
t.expect(fact("clean").gitBytes and fact("clean").gitBytes > 0, "Git's per-worktree record is measured apart from the checkout")
t.expect(fact("clean").bytes and fact("clean").bytes > 0, "the checkout is measured")
t.assertEqual(fact("gone").exists, false, "a missing directory is reported missing")
t.expect(fact("clean").lastActivity, "activity time comes from the worktree's own files")

local later = os.time() + 30 * 86400
local rowsReal = Worktrees.rows(entriesFound, factsByPath, {now = later})
local state = {}
for _, row in ipairs(rowsReal) do state[row.name] = row.state end
t.assertEqual(state.proj, "primary", "the repository's checkout is primary")
t.assertEqual(state.clean, "candidate", "clean is a candidate")
t.assertEqual(state.published, "candidate", "published-but-unmerged is a candidate with a stated reason")
t.assertEqual(state.dirty, "dirty", "dirty is review")
t.assertEqual(state.untracked, "dirty", "untracked is review")
t.assertEqual(state.unpublished, "unpublished", "unpublished is review")
t.assertEqual(state.detached, "unpublished", "a detached commit is unpublished")
t.assertEqual(state.locked, "locked", "locked is protected")
t.assertEqual(state.subs, "submodules", "submodules need an explicit decision")
t.assertEqual(state.gone, "missing", "gone is a prune")
t.assertEqual(state.codex, "candidate", "a clean Codex worktree is a candidate")
t.assertEqual(state.ignored, "candidate", "ignored files do not block, they warn")
local realPlan = Worktrees.plan(rowsReal)
local removable = {}
for _, row in ipairs(realPlan.removal) do removable[row.name] = true end
t.expect(removable.clean and removable.published and removable.codex and removable.ignored and #realPlan.removal == 4, "exactly the four clean worktrees are removable")
local ignoredRow
for _, row in ipairs(rowsReal) do if row.name == "ignored" then ignoredRow = row end end
t.expect(ignoredRow.warnings[1] and ignoredRow.warnings[1]:find("ignored files", 1, true), "the ignored output is a visible warning")

-- Git itself refuses a plain removal of a worktree with initialized submodules: the plan was right to hold it back.
local refused, refusal
run({"/usr/bin/git", "-C", P, "worktree", "remove", names.subs.path}, function(ok, output) refused, refusal = not ok, output end)
t.expect(refused and refusal:find("submodule", 1, true), "git refuses a worktree with submodules without force: " .. tostring(refusal))

-- Remove the removable set; everything else, and the repository, stays usable.
for _, row in ipairs(realPlan.removal) do
	local ok, output
	local command = Worktrees.removeCommand(row)
	run(command, function(a, b) ok, output = a, b end)
	t.expect(ok, "git removes " .. row.name .. ": " .. tostring(output))
end
local function exists(path) local ok; run({"/bin/test", "-d", path}, function(a) ok = a end); return ok end
for _, gone in ipairs({"clean", "published", "codex", "ignored"}) do t.expect(not exists(names[gone].path), gone .. " is removed") end
for _, kept in ipairs({"dirty", "untracked", "unpublished", "detached", "locked", "subs"}) do
	t.expect(exists(names[kept].path), kept .. " is preserved")
	local status
	run({"/usr/bin/git", "-C", names[kept].path, "status", "--porcelain"}, function(ok) status = ok end)
	t.expect(status, kept .. " is still a working checkout")
end
local log
run({"/usr/bin/git", "-C", P, "log", "--oneline", "-3"}, function(ok, output) log = output end)
t.expect(log and log:find("sub", 1, true), "the shared repository is intact")
local branches
run({"/usr/bin/git", "-C", P, "branch", "--list", "published", "clean"}, function(_, output) branches = output end)
t.expect(branches:find("published", 1, true) and branches:find("clean", 1, true), "removing a worktree leaves its branch")
t.expect(exists(P), "the primary checkout is untouched")

-- Prune only forgets the missing registration.
local prune = Worktrees.pruneCommand(state and (function() for _, row in ipairs(rowsReal) do if row.name == "gone" then return row end end end)())
local pruned
run(prune, function(ok) pruned = ok end)
t.expect(pruned, "prune runs")
local after
Service.list(run, {project}, function(value) after = value end)
local stillListed = {}
for _, row in ipairs(after) do stillListed[row.path:match("([^/]+)$")] = true end
t.expect(not stillListed.gone and stillListed.dirty and stillListed.locked and stillListed.subs, "prune drops the missing registration and nothing else")
os.execute("/bin/rm -rf " .. quote(tmp) .. " /private" .. quote(tmp))
os.exit(t.summary() and 0 or 1)
