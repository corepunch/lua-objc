local Model = require("apps.diskmap.Model")
local Projects = {}

-- Projects untouched for this long are worth reviewing first. Age comes from
-- the project's own folder, never from the generated artifact.
Projects.staleDays = 90
Projects.filters = {"All", "Not touched in 3 months", "Clean git tree"}

-- Parses `git status --porcelain=v1 --branch`. Returns nil for output that is
-- not from git (not a repository or git missing).
function Projects.parseGit(output)
	if type(output) ~= "string" or not output:match("^## ") then return nil end
	local header = output:match("^## ([^\n]*)")
	local changes = 0
	for line in output:gmatch("[^\n]+") do
		if not line:match("^## ") then changes = changes + 1 end
	end
	local ahead = tonumber(header:match("ahead (%d+)")) or 0
	local branch = header:match("^No commits yet on (%S+)") or header:match("^([^%.%s]+)") or header
	return {branch = branch, changes = changes, ahead = ahead, clean = changes == 0 and ahead == 0,
		upstream = header:find("...", 1, true) ~= nil}
end

function Projects.gitText(git)
	-- Short enough for the list's detail column.
	if git == nil then return "Not in git" end
	if git == false then return "Checking…" end
	if git.clean then return git.branch .. " · clean" end
	local parts = {}
	if git.changes > 0 then table.insert(parts, git.changes .. (git.changes == 1 and " uncommitted change" or " uncommitted changes")) end
	if git.ahead > 0 then table.insert(parts, git.ahead .. " unpushed") end
	return git.branch .. " · " .. table.concat(parts, ", ")
end

-- A project's name as people know it: a folder inside a repository is named
-- from the repository down ("my-app/apps/mobile/ios"), so the Pods of every
-- app in a monorepo are told apart; otherwise the folder's own name.
function Projects.displayName(path, repository)
	local name = path:match("([^/]+)$") or path
	if not repository or repository == path or path:sub(1, #repository + 1) ~= repository .. "/" then return name end
	return (repository:match("([^/]+)$") or repository) .. path:sub(#repository + 1)
end

-- Whether a folder below `root` lies in a hidden folder ("repo/.opencode",
-- "~/.cursor/extensions/x"): that is a tool's own data with a manifest in
-- it, not a project somebody works on, so its packages are not listed as a
-- project's build data.
function Projects.isToolFolder(path, root)
	local relative = path
	if root and root ~= "" and path:sub(1, #root + 1) == root .. "/" then relative = path:sub(#root + 1) end
	return relative:find("/%.[^/]") ~= nil
end

-- A project's folder as its row shows it, from the home folder, so two
-- projects with one name are told apart.
function Projects.location(path, home)
	if home and home ~= "" and path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
	return path
end

-- When a project was last worked on: the newest of the modification times
-- `stat` printed (one per line) for its git index, HEAD and source files.
-- At most `budget` files count, so a huge project cannot stall the page.
Projects.lastWorkedBudget = 5000
function Projects.lastWorked(output, budget)
	local newest, count = nil, 0
	for value in (output or ""):gmatch("[^\n]+") do
		local time = tonumber(value:match("^%s*(%d+)%s*$"))
		if time then
			count = count + 1
			if not newest or time > newest then newest = time end
			if count >= (budget or Projects.lastWorkedBudget) then break end
		end
	end
	return newest
end

-- Groups discovered artifact resources (leaves with a `project` path) by
-- project. `info[projectPath]` holds {modified = unix time, git = parsed or
-- nil, false while loading}.
function Projects.groups(model, info, now, filter, query)
	info, now = info or {}, now or os.time()
	local byProject, order, needle = {}, {}, (query or ""):lower()
	for _, row in ipairs(model.resources:leaves()) do
		if row.project then
			if not byProject[row.project] then
				byProject[row.project] = {path = row.project, name = row.projectName or row.project:match("([^/]+)$") or row.project, artifacts = {}, bytes = 0}
				table.insert(order, row.project)
			end
			local group = byProject[row.project]
			local m = model.measurements[row.id]
			local bytes = m and m.bytes
			table.insert(group.artifacts, {id = row.id, name = row.artifact or row.name, path = row.path,
				bytes = bytes, size = m and m.status == "calculating" and "Calculating…" or Model.size(bytes)})
			group.bytes = group.bytes + (bytes or 0)
		end
	end
	local rows = {}
	for _, path in ipairs(order) do
		local group = byProject[path]
		local details = info[path] or {}
		group.modified = details.modified
		group.age = details.modified and math.max(0, math.floor((now - details.modified) / 86400)) or nil
		group.git = details.git
		if details.git == nil and details.loaded ~= true then group.git = false end
		group.gitText = Projects.gitText(group.git)
		group.dirty = type(group.git) == "table" and not group.git.clean
		group.ageText = group.age == nil and "Age unknown" or group.age == 0 and "Today"
			or group.age == 1 and "Yesterday" or (group.age .. " days ago")
		local names = {}
		for _, artifact in ipairs(group.artifacts) do table.insert(names, artifact.name) end
		group.artifactText = table.concat(names, ", ")
		group.size = Model.size(group.bytes)
		local matches = needle == "" or (group.name .. " " .. group.path .. " " .. group.artifactText):lower():find(needle, 1, true)
		local passes = filter == nil or filter == Projects.filters[1]
			or (filter == Projects.filters[2] and group.age ~= nil and group.age >= Projects.staleDays)
			or (filter == Projects.filters[3] and type(group.git) == "table" and group.git.clean)
		if matches and passes then table.insert(rows, group) end
	end
	table.sort(rows, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.path < b.path
	end)
	return rows
end

return Projects
