local Builds = require("apps.diskmap.knowledge.Builds")
local Format = require("apps.diskmap.helpers.Format")
local Projects = {}

-- Build folders beside their projects: the search that finds them and the
-- facts that decide whether one may go. A build folder is `proven` when a
-- file inside it proves the build system made it (knowledge/Builds.lua);
-- it is `stale` when nothing in it or in its project was written for
-- `staleDays`: a build nobody has run or touched in that long costs nothing
-- to remove, since the next build makes it again anyway. A build older than
-- its sources is out of date and will be rebuilt by the next build whether
-- or not it is removed.
Projects.staleDays = 90

-- `find` arguments that print every build folder under `roots`: pruned at
-- generated folders and bundles, matching the rules' folder names.
function Projects.findArguments(roots)
	local argv = {"/usr/bin/find"}
	for _, root in ipairs(roots) do table.insert(argv, root) end
	for _, value in ipairs({"-maxdepth", tostring(Builds.depth), "-type", "d", "("}) do table.insert(argv, value) end
	for index, name in ipairs(Builds.dirNames()) do
		if index > 1 then table.insert(argv, "-o") end
		table.insert(argv, "-name"); table.insert(argv, name)
	end
	for _, value in ipairs({")", "-print", "-prune"}) do table.insert(argv, value) end
	return argv
end

-- The rules whose folder name is `name`.
function Projects.rulesFor(name)
	local rules = {}
	for _, rule in ipairs(Builds.rules) do if rule.dirName == name then table.insert(rules, rule) end end
	return rules
end

-- Whether a marker pattern ("*.xcodeproj") matches a file name.
function Projects.markerMatches(marker, name)
	if not marker:find("*", 1, true) then return marker == name end
	local pattern = "^" .. (marker:gsub("%p", "%%%0"):gsub("%%%*", ".*")) .. "$"
	return name:match(pattern) ~= nil
end

-- A folder inside a tool's own data (a worktree's `.claude`, a `.opencode`
-- install) is not a project of the person's.
function Projects.isToolFolder(parent, root)
	local rest = parent:sub(#root + 2)
	for part in rest:gmatch("[^/]+") do
		if part:sub(1, 1) == "." and part ~= ".claude" then return true end
	end
	return false
end

-- "my-app/apps/mobile/ios": the project named from its repository root.
function Projects.displayName(parent, repository)
	if repository and parent:sub(1, #repository) == repository then
		local rest = parent:sub(#repository + 2)
		local repo = repository:match("([^/]+)$") or repository
		return rest == "" and repo or (repo .. "/" .. rest)
	end
	return parent:match("([^/]+)$") or parent
end

-- The verdict for a build folder from its facts: `proven`, `built` (when
-- it was last written), `edited` (when its project's sources were), `now`.
function Projects.classify(facts, now)
	now = now or os.time()
	local built, edited = facts.built or 0, facts.edited or 0
	local idle = math.floor((now - math.max(built, edited)) / 86400)
	local stale = built > 0 and idle >= Projects.staleDays
	local parts = {}
	if built > 0 then table.insert(parts, "Last built " .. Format.age(built, now):lower()) end
	if edited > 0 then table.insert(parts, "sources edited " .. Format.age(edited, now):lower()) end
	if built > 0 and edited > built then table.insert(parts, "older than its sources, so the next build remakes it") end
	local detail = table.concat(parts, " · ")
	if not facts.proven then
		return {verdict = "review", stale = stale, reason = (detail ~= "" and (detail .. ". ") or "") .. "Nothing inside proves a build tool made this folder, so look before removing it."}
	end
	if stale then
		return {verdict = "safe", stale = true, reason = detail .. ". Nobody has built or edited this project in " .. Projects.staleDays .. " days; the next build makes it again."}
	end
	return {verdict = "review", stale = false, reason = (detail ~= "" and (detail .. ". ") or "") .. "The next build makes it again, but it is in use: removing it makes that build slower."}
end

return Projects
