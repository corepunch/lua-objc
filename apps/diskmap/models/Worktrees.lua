local Model = require("apps.diskmap.Model")
local Worktrees = {}

-- Leftover Git worktrees: linked checkouts that an AI tool or a person made
-- and nobody removed. This model only reads facts (from
-- `git worktree list --porcelain -z` and a few per-worktree queries) and
-- decides what may be offered; the controller runs the commands. Unknown
-- evidence is never treated as proof of abandonment.

-- A checkout touched within this many days is left for review: a recent
-- timestamp is evidence of recent work, not proof that a session owns it.
Worktrees.recentDays = 3
-- Application-managed locations: the owner's own archive flow comes first.
Worktrees.managers = {
	{name = "Codex", pattern = "/%.codex/worktrees/"},
	{name = "Claude", pattern = "/%.claude/worktrees/"},
}

-- Parses `git worktree list --porcelain -z`: fields end with NUL, a worktree
-- ends with an empty field. The first record is the primary checkout.
function Worktrees.parse(output)
	local entries, current = {}, nil
	for field in ((output or "") .. "\0"):gmatch("([^%z]*)%z") do
		if field == "" then
			if current then table.insert(entries, current); current = nil end
		else
			local key, value = field:match("^(%S+)%s?(.*)$")
			if key == "worktree" then
				if current then table.insert(entries, current) end
				current = {path = value, primary = #entries == 0}
			elseif current then
				if key == "HEAD" then current.head = value
				elseif key == "branch" then current.branch = value:gsub("^refs/heads/", "")
				elseif key == "detached" then current.detached = true
				elseif key == "bare" then current.bare = true
				elseif key == "locked" then current.locked = true; current.lockReason = value ~= "" and value or nil
				elseif key == "prunable" then current.prunable = true; current.pruneReason = value ~= "" and value or nil end
			end
		end
	end
	if current then table.insert(entries, current) end
	return entries
end

-- Who manages a worktree's location, or nil.
function Worktrees.manager(path)
	for _, manager in ipairs(Worktrees.managers) do
		if (path or ""):find(manager.pattern) then return manager.name end
	end
end

-- Merges the listings of several repositories without counting a worktree
-- twice: two searched roots can reach the same repository, and a worktree is
-- listed by every checkout of its repository. `listings` is
-- {{commonDir = path, entries = parse(...)}}; the identity is the worktree's
-- own path within its common Git directory.
function Worktrees.merge(listings)
	local seen, result = {}, {}
	for _, listing in ipairs(listings) do
		for index, entry in ipairs(listing.entries) do
			local key = (listing.commonDir or "") .. "\0" .. entry.path
			if not seen[key] then
				seen[key] = true
				local item = {}
				for field, value in pairs(entry) do item[field] = value end
				item.commonDir, item.repository = listing.commonDir, listing.entries[1] and listing.entries[1].path
				item.primary = index == 1
				table.insert(result, item)
			end
		end
	end
	return result
end

local function plural(count, word) return Model.plural(count, word) end

-- States, most protective first. A worktree is `candidate` only when every
-- piece of evidence is known and clean.
--   primary     the repository's own checkout
--   locked      Git's lock: someone asked for it to stay
--   kept        the user marked it Keep
--   missing     registered, but the directory is gone (a prune, not a deletion)
--   active      a process or session is confirmed to use it ("In use")
--   recent      touched in the last few days; no owner is confirmed
--   dirty       uncommitted or untracked files
--   unpublished commits that exist nowhere else
--   unknown     a needed fact could not be read
--   submodules  initialized submodules: Git refuses a plain removal
--   candidate   clean, published, idle
function Worktrees.classify(entry, facts, options)
	options = options or {}
	facts = facts or {}
	local reasons = {}
	local function add(text) table.insert(reasons, text) end
	if entry.primary then
		return {state = "primary", eligible = false, reasons = {"The repository's own checkout is never offered."}}
	end
	if entry.locked then
		return {state = "locked", eligible = false, reasons = {"Locked in Git" .. (entry.lockReason and (": " .. entry.lockReason) or ".")}}
	end
	if options.kept then
		return {state = "kept", eligible = false, reasons = {"Marked Keep."}}
	end
	if entry.prunable or facts.exists == false then
		return {state = "missing", eligible = false, prune = true, reasons = {"The directory is gone; only Git's record of it remains."}}
	end
	local state = "candidate"
	local warnings = {}
	if facts.active then
		state = "active"; add("A session or process is using it.")
	elseif facts.lastActivity and options.now and (options.now - facts.lastActivity) < Worktrees.recentDays * 86400 then
		-- Diskmap cannot see sessions: say what the timestamp shows and no more.
		state = "recent"
		add("Its files or Git record changed " .. Model.ago(math.floor((options.now - facts.lastActivity) / 86400)):lower()
			.. ". Diskmap cannot tell whether a session still uses it, so it waits for your review.")
	end
	local manager = Worktrees.manager(entry.path)
	if facts.changes == nil or facts.untracked == nil or facts.unpublished == nil then
		if state == "candidate" then state = "unknown" end
		add("Its Git state could not be read.")
	end
	if (facts.changes or 0) > 0 or (facts.untracked or 0) > 0 then
		if state == "candidate" or state == "unknown" then state = "dirty" end
		local parts = {}
		if (facts.changes or 0) > 0 then table.insert(parts, plural(facts.changes, "uncommitted change")) end
		if (facts.untracked or 0) > 0 then table.insert(parts, plural(facts.untracked, "untracked file")) end
		add(table.concat(parts, " and ") .. ".")
	end
	if (facts.unpublished or 0) > 0 then
		if state == "candidate" or state == "unknown" then state = "unpublished" end
		add(plural(facts.unpublished, "commit") .. " exist only here.")
	end
	if state == "candidate" and (facts.submodules or 0) > 0 then
		state = "submodules"; add(plural(facts.submodules, "initialized submodule") .. "; Git will not remove it without force.")
	end
	if facts.ignoredBytes and facts.ignoredBytes > 0 then
		table.insert(warnings, Model.size(facts.ignoredBytes) .. " of ignored files (build output, local settings) go with it.")
	end
	if state ~= "candidate" and manager then
		add("To remove it with its session, archive the session in " .. manager .. "; " .. manager .. " deletes the worktree it made.")
	end
	if state == "candidate" then
		if facts.merged == true then add("Its commits are merged into " .. (facts.defaultBranch or "the default branch") .. ".")
		elseif facts.merged == false then add("Not merged, but every commit is on a remote.")
		else add("Every commit is on a remote.") end
		if facts.lastActivity == nil then add("Session ownership and activity are unknown.") end
	end
	return {state = state, eligible = state == "candidate", reasons = reasons, warnings = warnings}
end

local ROLE = {primary = "Repository", locked = "Locked", kept = "Kept", missing = "Missing", active = "In use", recent = "Recently touched", dirty = "Has changes",
	unpublished = "Unpublished", unknown = "Unknown", submodules = "Submodules", candidate = "Ready"}
Worktrees.roleNames = ROLE
local COLORS = {primary = "systemGray", locked = "systemBlue", kept = "systemBlue", missing = "systemGray", active = "systemRed", recent = "systemYellow", dirty = "systemOrange",
	unpublished = "systemOrange", unknown = "systemGray", submodules = "systemOrange", candidate = "systemGreen"}

-- Rows for the worktree list and the plan. `facts[path]` holds the measured
-- evidence; `kept(path)` reports Keep. Storage is split three ways and never
-- counts the shared object database once per worktree: `sourceBytes` is the
-- checkout without its generated output, `generatedBytes` the discovered
-- build artifacts inside it, `gitBytes` Git's own record for this worktree
-- (worktrees/<id>, with its submodule repositories).
function Worktrees.rows(entries, facts, options)
	options = options or {}
	local rows = {}
	for _, entry in ipairs(entries) do
		local fact = facts[entry.path] or {}
		local result = Worktrees.classify(entry, fact, {now = options.now, kept = options.kept and options.kept(entry.path)})
		local worktreeBytes, gitBytes, generated = fact.bytes, fact.gitBytes, math.min(fact.generatedBytes or 0, fact.bytes or 0)
		local manager = Worktrees.manager(entry.path)
		local name = entry.path:match("([^/]+)$") or entry.path
		-- Codex names a worktree after its repository inside a folder of its own:
		-- the folder tells worktrees of one repository apart.
		local repoName = entry.repository and entry.repository:match("([^/]+)$")
		if not entry.primary and repoName == name then name = (entry.path:match("([^/]+)/[^/]+$") or "") .. "/" .. name end
		local row = {id = entry.path, path = entry.path, name = name, repository = entry.repository, commonDir = entry.commonDir,
			branch = entry.branch, detached = entry.detached, head = entry.head and entry.head:sub(1, 8), manager = manager,
			state = result.state, eligible = result.eligible, prune = result.prune, reasons = result.reasons, warnings = result.warnings,
			roleLabel = ROLE[result.state], color = COLORS[result.state], icon = "arrow.triangle.branch",
			worktreeBytes = worktreeBytes, gitBytes = gitBytes, generatedBytes = worktreeBytes and generated or nil,
			sourceBytes = worktreeBytes and (worktreeBytes - generated) or nil,
			ignoredBytes = fact.ignoredBytes, submodules = fact.submodules or 0, lastActivity = fact.lastActivity,
			bytes = (worktreeBytes or 0) + (gitBytes or 0)}
		row.size = (worktreeBytes or gitBytes) and Model.size(row.bytes) or "Not measured"
		local repo = entry.repository and (entry.repository:match("([^/]+)$") or entry.repository) or "repository"
		row.subtitle = repo .. " · " .. (entry.detached and ("detached " .. (row.head or "")) or (entry.branch or "no branch"))
			.. (manager and (" · " .. manager) or "")
		-- A filesystem timestamp shows a change, not a use.
		row.lastUse = fact.lastActivity and options.now and ("Changed " .. Model.ago(math.floor((options.now - fact.lastActivity) / 86400)):lower())
			or (entry.primary and "" or "Last change unknown")
		table.insert(rows, row)
	end
	table.sort(rows, function(a, b)
		local ea, eb = a.eligible and 0 or 1, b.eligible and 0 or 1
		if ea ~= eb then return ea < eb end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	return rows
end

-- The review: what Git can remove now, what needs a human, what only needs a
-- prune. Totals separate the bytes a removal frees from the bytes to review.
function Worktrees.plan(rows)
	local plan = {removal = {}, review = {}, prune = {}, protected = {}, removalBytes = 0, reviewBytes = 0, ignoredBytes = 0,
		sourceBytes = 0, generatedBytes = 0, gitBytes = 0}
	for _, row in ipairs(rows) do
		if row.eligible then
			table.insert(plan.removal, row)
			plan.removalBytes = plan.removalBytes + row.bytes
			plan.sourceBytes = plan.sourceBytes + (row.sourceBytes or 0)
			plan.generatedBytes = plan.generatedBytes + (row.generatedBytes or 0)
			plan.gitBytes = plan.gitBytes + (row.gitBytes or 0)
			plan.ignoredBytes = plan.ignoredBytes + (row.ignoredBytes or 0)
		elseif row.prune then table.insert(plan.prune, row)
		elseif row.state == "primary" or row.state == "locked" or row.state == "kept" then table.insert(plan.protected, row)
		else
			table.insert(plan.review, row)
			plan.reviewBytes = plan.reviewBytes + row.bytes
		end
	end
	plan.ready = #plan.removal > 0
	return plan
end

-- `git worktree remove` without --force refuses a dirty, locked or
-- submodule-bearing worktree and removes ignored files with the directory.
function Worktrees.removeCommand(row)
	if not row or row.state ~= "candidate" or not row.repository then return nil end
	return {"/usr/bin/git", "-C", row.repository, "worktree", "remove", row.path}
end

-- Only registrations whose directory is gone are pruned; the command never
-- touches an existing checkout.
function Worktrees.pruneCommand(row)
	if not row or not row.prune or not row.repository then return nil end
	return {"/usr/bin/git", "-C", row.repository, "worktree", "prune"}
end

-- Every worktree is revalidated from fresh facts just before its removal.
function Worktrees.revalidate(row, entry, facts, options)
	if not entry then return false, {code = "gone", message = "Git no longer lists this worktree."} end
	local result = Worktrees.classify(entry, facts, options)
	if not result.eligible then return false, {code = result.state, message = result.reasons[1] or "It is no longer eligible."} end
	return true
end

-- The text of the single confirmation for a batch.
function Worktrees.confirmation(plan)
	local lines = {}
	for _, row in ipairs(plan.removal) do
		table.insert(lines, row.name .. " · " .. row.subtitle .. " · " .. row.size .. " · " .. row.lastUse)
	end
	local managed = {}
	for _, row in ipairs(plan.removal) do if row.manager then managed[row.manager] = true end end
	local names = {}
	for name in pairs(managed) do table.insert(names, name) end
	table.sort(names)
	return "Remove " .. plural(#plan.removal, "worktree") .. "?\n\n" .. table.concat(lines, "\n")
		.. "\n\nRemoves the checkouts and Git's record of them, " .. Model.size(plan.removalBytes) .. " in all, including "
		.. Model.size(plan.ignoredBytes) .. " of ignored files. The repository and its history stay. Each worktree is checked again just before it is removed."
		.. (#names > 0 and ("\n\n" .. table.concat(names, " and ") .. " keep their own session lists; archive these there if you want them tidy.") or "")
end

return Worktrees
