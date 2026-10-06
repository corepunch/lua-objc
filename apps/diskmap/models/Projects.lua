local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
-- The projects whose build folders a scan found: discovered artifact
-- locations (leaves with a `project` path), grouped by project. What git and
-- the project folder say about each lives in the store's `projectInfo`,
-- by project path: {modified = unix time, git = parsed or nil, loaded}.
local Projects
Projects = Model:extend("projects", {primaryKey = "path", source = function() return Projects:groups() end})

-- Projects untouched for this long are worth reviewing first. Age comes from
-- the project's own folder, never from the generated artifact.
Projects.staleDays = 90
Projects.filters = Model.enum({"All", "Not touched in 3 months", "Clean git tree"})

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

-- The projects a filter leaves, largest first.
function Projects:groups(filter, now)
	local model = Model.db
	local info = model.projectInfo or {}
	now = now or os.time()
	local byProject, order = {}, {}
	for _, row in ipairs(Locations:leaves()) do
		if row.project then
			if not byProject[row.project] then
				byProject[row.project] = {path = row.project, name = row.projectName or row.project:match("([^/]+)$") or row.project, artifacts = {}, bytes = 0}
				table.insert(order, row.project)
			end
			local group = byProject[row.project]
			local m = model.measurements[row.id]
			local bytes = m and m.bytes
			table.insert(group.artifacts, {id = row.id, name = row.artifact or row.name, path = row.path,
				bytes = bytes, size = Format.size(bytes)})
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
		group.size = Format.size(group.bytes)
		local passes = filter == nil or filter == Projects.filters[1]
			or (filter == Projects.filters[2] and group.age ~= nil and group.age >= Projects.staleDays)
			or (filter == Projects.filters[3] and type(group.git) == "table" and group.git.clean)
		if passes then table.insert(rows, group) end
	end
	table.sort(rows, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.path < b.path
	end)
	return rows
end

-- Generated artifacts within a location, separate from the whole folder's
-- measured bytes. Missing measurements remain unknown rather than zero.
function Projects:bytesWithin(path)
	local bytes, measured = 0, false
	for _, row in ipairs(Locations:leaves()) do
		if row.project and row.path and (row.path == path or row.path:sub(1, #path + 1) == path .. "/") then
			local measurement = row:measurement()
			if measurement and measurement.bytes ~= nil then
				bytes, measured = bytes + measurement.bytes, true
			end
		end
	end
	return measured and bytes or nil
end

function Projects:badge()
	local bytes = 0
	for _, group in ipairs(self:groups(self.filters[1])) do bytes = bytes + group.bytes end
	return bytes > 0 and require("apps.diskmap.helpers.Format").size(bytes) or nil
end

function Projects.items(group)
	local result = {}
	for _, artifact in ipairs(group.artifacts) do
		table.insert(result, {path = artifact.path, name = artifact.name .. " · " .. group.name, bytes = artifact.bytes,
			source = "Projects", consequence = "Generated by the project's tools and recreated by its next build or install."
				.. (group.dirty and " This project has uncommitted or unpushed work; its sources are not touched." or "")})
	end
	return result
end


return Projects
