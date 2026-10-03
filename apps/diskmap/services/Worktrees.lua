local Worktrees = require("apps.diskmap.helpers.Worktrees")
local Knowledge = require("apps.diskmap.knowledge.Paths")
local Service = {}

-- Git queries for the worktree review. Every function takes `run(argv,
-- completion(ok, output))`, the app's command runner, so the same code runs
-- against the real Git in a test. Nothing here writes: removal is the
-- controller's decision and goes through Worktrees.removeCommand.

local GIT = "/usr/bin/git"

local function lines(output)
	local result = {}
	for line in (output or ""):gmatch("[^\n]+") do table.insert(result, line) end
	return result
end

local function trim(value) return ((value or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Repositories under `roots`: every folder holding a `.git` entry (a folder,
-- or a file for a linked worktree), found without descending into
-- dependencies. Identified by Git's common directory, so two roots reaching
-- one repository, or a repository and its worktrees, list it once.
Service.depth = 5
function Service.repositories(run, roots, completion)
	local argv = {"/usr/bin/find"}
	for _, root in ipairs(roots) do table.insert(argv, root) end
	for _, value in ipairs({"-maxdepth", tostring(Service.depth), "("}) do table.insert(argv, value) end
	for index, name in ipairs(Knowledge.repositoryPrune) do
		if index > 1 then table.insert(argv, "-o") end
		table.insert(argv, "-name"); table.insert(argv, name)
	end
	for _, value in ipairs({")", "-prune", "-o", "-name", ".git", "-print"}) do table.insert(argv, value) end
	run(argv, function(ok, output)
		local found, seen, repos = lines(output), {}, {}
		local function step(index)
			if index > #found then completion(repos); return end
			local path = found[index]
			if path:sub(1, 1) ~= "/" then step(index + 1); return end
			local checkout = path:gsub("/%.git$", "")
			run({GIT, "-C", checkout, "rev-parse", "--path-format=absolute", "--git-common-dir"}, function(good, common)
				common = trim(common)
				-- A submodule's repository lives under its parent's modules folder and is
				-- not a repository to review worktrees of; its storage belongs to the
				-- worktree that initialised it.
				if good and common ~= "" and not seen[common] and not common:find("/modules/", 1, true) then
					seen[common] = true
					table.insert(repos, {path = checkout, commonDir = common})
				end
				step(index + 1)
			end)
		end
		step(1)
	end)
end

-- The merged worktree list of every repository.
function Service.list(run, repos, completion)
	local listings = {}
	local function step(index)
		if index > #repos then completion(Worktrees.merge(listings)); return end
		local repo = repos[index]
		run({GIT, "-C", repo.path, "worktree", "list", "--porcelain", "-z"}, function(ok, output)
			if ok then table.insert(listings, {commonDir = repo.commonDir, entries = Worktrees.parse(output)}) end
			step(index + 1)
		end)
	end
	step(1)
end

-- Evidence for one worktree. Fields stay nil when Git could not answer; the
-- model treats nil as unknown, never as clean. `measure(paths, completion)`
-- sizes folders.
function Service.facts(run, measure, entry, completion)
	local facts = {}
	local path = entry.path
	local function git(args, done)
		local argv = {GIT, "-C", path}
		for _, value in ipairs(args) do table.insert(argv, value) end
		run(argv, done)
	end
	local steps = {}
	local function add(fn) table.insert(steps, fn) end
	add(function(done) run({"/bin/test", "-d", path}, function(ok) facts.exists = ok; done() end) end)
	-- A repository's own checkout is never offered, so it is neither measured
	-- nor queried: it is context for the worktrees made from it.
	if entry.primary then
		local function step(index)
			if index > #steps then completion(facts); return end
			steps[index](function() step(index + 1) end)
		end
		step(1)
		return
	end
	-- Activity is read before any other Git command: `git status` refreshes
	-- the index, and its own write must not read as recent work.
	add(function(done)
		if facts.exists == false then done(); return end
		git({"rev-parse", "--absolute-git-dir"}, function(ok, output)
			facts.adminDir = ok and trim(output) or nil
			if not facts.adminDir then done(); return end
			run({"/usr/bin/stat", "-f", "%m", facts.adminDir .. "/HEAD", facts.adminDir .. "/index", path}, function(_, times)
				for value in (times or ""):gmatch("%d+") do
					value = tonumber(value)
					if not facts.lastActivity or value > facts.lastActivity then facts.lastActivity = value end
				end
				done()
			end)
		end)
	end)
	add(function(done)
		if facts.exists == false then done(); return end
		git({"status", "--porcelain=v1", "-z", "--untracked-files=normal"}, function(ok, output)
			if ok then
				facts.changes, facts.untracked = 0, 0
				local records = {}
				for record in (output or ""):gmatch("([^%z]+)%z") do table.insert(records, record) end
				local index = 1
				while index <= #records do
					local record = records[index]
					if record:sub(1, 2) == "??" then facts.untracked = facts.untracked + 1
					else
						facts.changes = facts.changes + 1
						-- A rename or copy is followed by its source path as a bare record.
						if record:match("^[RC]") or record:match("^.[RC]") then index = index + 1 end
					end
					index = index + 1
				end
			end
			done()
		end)
	end)
	add(function(done)
		if facts.exists == false then done(); return end
		-- A branch's commits survive its worktree; they are "unpublished" when no
		-- remote has them. A detached HEAD's commits survive only if some ref has them.
		local args = entry.detached and {"rev-list", "--count", "HEAD", "--not", "--branches", "--remotes", "--tags"}
			or {"rev-list", "--count", "HEAD", "--not", "--remotes"}
		git(args, function(ok, output) if ok then facts.unpublished = tonumber(trim(output)) end; done() end)
	end)
	add(function(done)
		if facts.exists == false then done(); return end
		git({"symbolic-ref", "--short", "-q", "refs/remotes/origin/HEAD"}, function(ok, output)
			local default = ok and trim(output) or ""
			if default == "" then default = "main" end
			facts.defaultBranch = default
			git({"merge-base", "--is-ancestor", "HEAD", default}, function(good, _)
				-- merge-base exits 1 for "not an ancestor" and 128 for an unknown ref; the
				-- runner reports both as failure, so distinguish with rev-parse.
				if good then facts.merged = true; done(); return end
				git({"rev-parse", "--verify", "-q", default}, function(known) if known then facts.merged = false end; done() end)
			end)
		end)
	end)
	add(function(done)
		if facts.exists == false then done(); return end
		git({"submodule", "status"}, function(ok, output)
			if ok then
				facts.submodules = 0
				for _, line in ipairs(lines(output)) do if line:sub(1, 1) ~= "-" then facts.submodules = facts.submodules + 1 end end
			end
			done()
		end)
	end)
	add(function(done)
		if facts.exists == false then done(); return end
		git({"ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"}, function(ok, output)
			local ignored = {}
			if ok then for record in (output or ""):gmatch("([^%z]+)%z") do table.insert(ignored, path .. "/" .. record:gsub("/$", "")) end end
			if #ignored == 0 or not measure then facts.ignoredBytes = ok and 0 or nil; done(); return end
			measure(ignored, function(sizes)
				facts.ignoredBytes = 0
				for _, size in ipairs(sizes or {}) do facts.ignoredBytes = facts.ignoredBytes + (size or 0) end
				done()
			end)
		end)
	end)
	add(function(done)
		local targets = {}
		if facts.exists ~= false then table.insert(targets, path) end
		if facts.adminDir then table.insert(targets, facts.adminDir) end
		if #targets == 0 or not measure then done(); return end
		measure(targets, function(sizes)
			local index = 1
			if facts.exists ~= false then facts.bytes = sizes and sizes[index]; index = index + 1 end
			if facts.adminDir then facts.gitBytes = sizes and sizes[index] end
			done()
		end)
	end)
	local function step(index)
		if index > #steps then completion(facts); return end
		steps[index](function() step(index + 1) end)
	end
	step(1)
end

-- Evidence for every entry, `Service.parallel` worktrees at a time: each
-- worktree's queries run in order, worktrees overlap. `progress(done, total)`
-- reports each finished worktree. Completes with facts by path.
Service.parallel = 4
function Service.allFacts(run, measure, entries, completion, progress)
	local facts, total, finished, next = {}, #entries, 0, 1
	if total == 0 then completion(facts); return end
	local function start()
		if next > total then return end
		local entry = entries[next]
		next = next + 1
		Service.facts(run, measure, entry, function(value)
			facts[entry.path] = value
			finished = finished + 1
			if progress then progress(finished, total) end
			if finished == total then completion(facts) else start() end
		end)
	end
	for _ = 1, math.min(Service.parallel, total) do start() end
end

return Service
