local Model = require("data.model")
local Items = require("apps.diskmap.models.Items")
local Locations = require("apps.diskmap.knowledge.Locations")
local Builds = require("apps.diskmap.knowledge.Builds")
local Categories = require("apps.diskmap.knowledge.Categories")
local Explain = require("apps.diskmap.helpers.Explain")
local Leftovers = require("apps.diskmap.helpers.Leftovers")
local Verify = require("apps.diskmap.helpers.Verify")
local Xcode = require("apps.diskmap.helpers.Xcode")
local Simulators = require("apps.diskmap.helpers.Simulators")
local Projects = require("apps.diskmap.helpers.Projects")
local Worktrees = require("apps.diskmap.helpers.Worktrees")
local Volumes = require("apps.diskmap.helpers.Volumes")
local Format = require("apps.diskmap.helpers.Format")

-- The sources: one loader per category that asks the service what is on
-- this Mac, measures it in one walk and writes the rows (models/Items.lua).
-- Nothing scans the whole disk; every loader knows where to look
-- (knowledge/Locations.lua) or asks the tool that knows (simctl, git, the
-- build system's markers). Loaders run one after another; each one's rows
-- appear as soon as it finishes, and a running measurement can be
-- cancelled by starting another.
local Sources = {}; Sources.__index = Sources

Sources.order = {"xcode", "simulators", "packages", "editors", "ai", "system", "projects", "worktrees"}
-- A child of an expanded folder is listed from this size; smaller ones are noise.
Sources.childMinimumBytes = 1e6

local VERDICTS = {safe = {verdict = "safe", action = "trash"}, review = {verdict = "review", action = "trash"},
	owner = {verdict = "owner", action = "none"}, system = {verdict = "system", action = "none"}}

-- `router.refresh()` draws the pages again; `router.changed()` reports the
-- measurement's state.
function Sources.new(service, home, router)
	return setmetatable({service = service, home = home, router = router, generation = 0, jobs = {}}, Sources)
end

function Sources:expand(path)
	if path == "~" then return self.home end
	if path:sub(1, 2) == "~/" then return self.home .. path:sub(2) end
	if path:sub(1, 7) == "$TMPDIR" then
		local tmp = self.service.tmpdir()
		if not tmp or tmp == "" then return nil end
		local rest = path:sub(8)
		if rest == "/../C" then return (tmp:gsub("/[^/]+$", "")) .. "/C" end
		return tmp .. rest
	end
	return path
end

function Sources:cancel()
	self.generation = self.generation + 1
	for _, job in ipairs(self.jobs) do self.service.cancel(job) end
	self.jobs = {}
end

-- Measures `paths` for the loader of the current generation; a stale
-- completion is dropped.
function Sources:measure(paths, exclusions, completion)
	local generation = self.generation
	if #paths == 0 then completion({}); return end
	local job = self.service.measure(paths, exclusions or {}, function(records)
		if generation ~= self.generation then return end
		completion(records or {})
	end)
	if job then table.insert(self.jobs, job) end
end

-- Every path the knowledge table names, so an expanded folder never lists
-- a child another entry presents.
function Sources:claimed()
	if not self.claimedPaths then
		self.claimedPaths = {}
		for _, entry in ipairs(Locations.list) do
			local path = self:expand(entry.path)
			if path then self.claimedPaths[path] = true end
		end
		self.claimedPaths[self:expand(Xcode.derivedData)] = true
		self.claimedPaths[self:expand(Xcode.archives)] = true
		for _, support in ipairs(Xcode.deviceSupport) do self.claimedPaths[self:expand(support.path)] = true end
		self.claimedPaths[self:expand("~/Library/Developer/CoreSimulator/Devices")] = true
	end
	return self.claimedPaths
end

local function verdictOf(remove)
	local mapping = VERDICTS[remove] or VERDICTS.review
	return mapping.verdict, mapping.action
end

-- "vadimcn.vscode-lldb-1.11.0" -> "vadimcn.vscode-lldb", {1, 11, 0}
local function splitVersion(name)
	local stem, version = name:match("^(.-)[%-%s]v?(%d+[%.%d]*)[%-%w]*$")
	if not stem then stem, version = "", name:match("^v?(%d+[%.%d]*)$") end
	if not version then return name, nil end
	local parts = {}
	for number in version:gmatch("%d+") do table.insert(parts, tonumber(number)) end
	return stem, parts
end
local function newer(a, b)
	for index = 1, math.max(#a, #b) do
		local x, y = a[index] or 0, b[index] or 0
		if x ~= y then return x > y end
	end
	return false
end

-- Among children named "<stem>-<version>", every version but the newest
-- of its stem is a leftover.
function Sources.olderVersions(children)
	local newest = {}
	for _, child in ipairs(children) do
		local stem, parts = splitVersion(child.name)
		if parts and (not newest[stem] or newer(parts, newest[stem].parts)) then newest[stem] = {name = child.name, parts = parts} end
	end
	local older = {}
	for _, child in ipairs(children) do
		local stem, parts = splitVersion(child.name)
		if parts and newest[stem] and newest[stem].name ~= child.name then older[child.name] = newest[stem].name end
	end
	return older
end

-- What the installed apps say a folder is (helpers/Explain), once Spotlight
-- answered; before that, nothing is called unclaimed.
function Sources:facts()
	local apps = Model.db.installedApplications
	if apps ~= self.factsFor or not self.explainFacts then
		self.factsFor = apps
		self.explainFacts = {home = self.home, apps = apps and Leftovers.index(apps) or nil}
	end
	return self.explainFacts
end

-- A child of an expanded location as a row: a known child's note, else what
-- the installed apps and macOS's conventions say, else the parent's.
function Sources:childRow(entry, parentPath, child, older)
	-- An asset class reads by its name, not its folder: "com_apple_MobileAsset_UAF_LinguisticData".
	local name = child.name:match("^com_apple_MobileAsset_(.+)$")
	name = name and name:gsub("^UAF_", ""):gsub("_", " ") or child.name
	local row = {id = child.path, path = child.path, name = name, section = entry.section, parent = parentPath,
		bytes = child.bytes, used = child.used, state = "measured", partial = child.partial, owner = entry.owner, what = entry.what, admin = entry.admin}
	local known = entry.children and entry.children[child.name]
	local verdict, action = verdictOf(known and known.remove or entry.remove)
	if known then
		row.what, row.settings = known.what, known.settings
		if known.name then row.name = known.name end
		row.reason = known.what
	elseif entry.owners then
		local answer = Explain.path(child.path, self:facts())
		if answer and answer.owner then
			row.owner, row.what = answer.owner, answer.what
			if answer.apple then
				verdict, action = "system", "none"
				row.reason = answer.owner .. " writes it and macOS manages it."
			else
				row.bundleId = Verify.bundleId(child.path)
				row.reason = answer.owner .. " rebuilds it. Quit " .. answer.owner .. " before removing it."
			end
		elseif answer and answer.unclaimed then
			row.owner, row.what = "No installed app", answer.what
			verdict, action = "review", "trash"
			row.reason = "Not part of macOS, and no installed app claims it: it may belong to an app you removed. Look inside before removing it."
		else
			-- Nothing names the writer: the folder is what its place says it is.
			row.owner, row.reason = "Unknown", "Diskmap cannot say what writes it. " .. entry.what
		end
	else
		row.reason = entry.what
	end
	if older and older[child.name] then
		verdict, action = "safe", "trash"
		row.reason = "An older version beside " .. older[child.name] .. "; the newer one is the one in use."
	end
	if entry.admin then action = "none" end
	row.verdict, row.action = verdict, action
	return row
end

-- The rows of a category's knowledge entries: one per present location,
-- or one per child of an expanded one.
function Sources:locationRows(category, done)
	local entries, paths = {}, {}
	for _, entry in ipairs(Locations.of(category)) do
		local path = self:expand(entry.path)
		if path then table.insert(entries, entry); table.insert(paths, path) end
	end
	self:measure(paths, {}, function(records)
		local rows, claimed = {}, self:claimed()
		for index, entry in ipairs(entries) do
			local record, path = records[index], paths[index]
			if record and record.state ~= "missing" then
				if entry.expand and record.state == "measured" then
					local older = entry.versions and Sources.olderVersions(record.children) or nil
					for _, child in ipairs(record.children) do
						-- Children too small to matter are left out, unless the dictionary names them.
						local named = entry.children and entry.children[child.name]
						if not claimed[child.path] and (named or (child.bytes or 0) >= Sources.childMinimumBytes) then
							table.insert(rows, self:childRow(entry, path, child, older))
						end
					end
				else
					local verdict, action = verdictOf(entry.remove)
					if entry.admin then action = "none" end
					table.insert(rows, {id = path, path = path, name = entry.name, section = entry.section, owner = entry.owner, what = entry.what,
						bytes = record.bytes, used = record.used, state = record.state, partial = record.partial, verdict = verdict, action = action, admin = entry.admin,
						settings = entry.settings, reason = entry.what .. " (Checked " .. entry.checked .. ".)"})
				end
			end
		end
		done(rows)
	end)
end

function Sources:packages(done) self:locationRows("packages", done) end
function Sources:editors(done) self:locationRows("editors", done) end
function Sources:ai(done) self:locationRows("ai", done) end

-- Xcode: DerivedData per project, device support per OS version, archives,
-- and the fixed caches.
function Sources:xcode(done)
	local service = self.service
	local derived, archives = self:expand(Xcode.derivedData), self:expand(Xcode.archives)
	local supports = {}
	for _, support in ipairs(Xcode.deviceSupport) do table.insert(supports, self:expand(support.path)) end
	local roots = {derived, archives}
	for _, path in ipairs(supports) do table.insert(roots, path) end
	self:locationRows("xcode", function(rows)
		self:measure(roots, {}, function(records)
			local derivedEntries = {}
			for _, child in ipairs(records[1] and records[1].children or {}) do
				if child.directory then
					local plist = service.readPropertyList(child.path .. "/info.plist")
					local workspace = type(plist) == "table" and plist.WorkspacePath or nil
					local entry = {name = child.name, path = child.path, bytes = child.bytes, used = child.used, workspace = workspace}
					if workspace then entry.exists = service.exists(workspace) == true end
					table.insert(derivedEntries, entry)
				end
			end
			for _, row in ipairs(Xcode.derivedRows(derivedEntries)) do row.section = "derived"; table.insert(rows, row) end
			local supportEntries = {}
			for index, support in ipairs(Xcode.deviceSupport) do
				for _, child in ipairs(records[index + 2] and records[index + 2].children or {}) do
					if child.directory then table.insert(supportEntries, {platform = support.platform, name = child.name, path = child.path, bytes = child.bytes, used = child.used}) end
				end
			end
			for _, row in ipairs(Xcode.supportRows(supportEntries)) do row.section = "support"; table.insert(rows, row) end
			-- Archives live one folder deeper, under the day they were made.
			local archivePaths = {}
			for _, day in ipairs(records[2] and records[2].children or {}) do
				if day.directory then
					for _, entry in ipairs(service.children(day.path)) do
						if entry.name:match("%.xcarchive$") then table.insert(archivePaths, {path = entry.path, name = entry.name, date = day.name}) end
					end
				end
			end
			local list = {}
			for _, archive in ipairs(archivePaths) do table.insert(list, archive.path) end
			self:measure(list, {}, function(measured)
				local entries = {}
				for index, archive in ipairs(archivePaths) do
					local record = measured[index] or {}
					table.insert(entries, {path = archive.path, name = archive.name, date = archive.date, bytes = record.bytes, used = record.used,
						plist = service.readPropertyList(archive.path .. "/Info.plist")})
				end
				for _, row in ipairs(Xcode.archiveRows(entries)) do row.section = "archives"; table.insert(rows, row) end
				done(rows)
			end)
		end)
	end)
end

-- Simulators: what simctl lists, joined with the measured device folders,
-- and the installed runtimes.
function Sources:simulators(done)
	local service = self.service
	local devicesRoot = self:expand("~/Library/Developer/CoreSimulator/Devices")
	local now = os.time()
	self:locationRows("simulators", function(rows)
		service.simulatorDevices(function(listed, deviceError)
			service.simulatorRuntimes(function(runtimes, runtimeError)
				self:measure({devicesRoot}, {}, function(records)
					local folders = {}
					for _, child in ipairs(records[1] and records[1].children or {}) do
						if child.directory and child.name:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
							local plist = service.readPropertyList(child.path .. "/device.plist")
							folders[child.name] = {path = child.path, bytes = child.bytes, used = child.used, state = "measured",
								name = type(plist) == "table" and plist.name or nil, runtime = type(plist) == "table" and plist.runtime or nil}
						end
					end
					local devices = listed and listed.devices or {}
					for _, row in ipairs(Simulators.deviceRows(devices, folders, now)) do row.section = "devices"; table.insert(rows, row) end
					for _, row in ipairs(Simulators.runtimeRows(runtimes, devices, now)) do row.section = "runtimes"; table.insert(rows, row) end
					self.notes = self.notes or {}
					self.notes.simulators = deviceError or runtimeError
					done(rows)
				end)
			end)
		end)
	end)
end

-- System Data: the volumes by their own size, then the asset store, caches,
-- logs and temporary files, each child explained by owner.
function Sources:system(done)
	local service = self.service
	local function finish()
		service.volumes(function(volumes)
			self:locationRows("system", function(rows)
				for _, volume in ipairs(volumes or {}) do
					local role = Volumes.roles[volume.role]
					if role then
						table.insert(rows, {id = "volume:" .. volume.role, name = role.name, section = "volumes", owner = "macOS", what = role.what,
							bytes = volume.bytes, state = "measured", verdict = "system", action = "none", reason = role.what})
					end
				end
				done(rows)
			end)
		end)
	end
	if Model.db.installedApplications ~= nil then finish(); return end
	local generation = self.generation
	service.installedApplications(function(apps)
		if generation ~= self.generation then return end
		Model.db.installedApplications = apps or false
		finish()
	end)
end

-- The folders the project search covers: the conventional ones that exist,
-- plus those the person added.
function Sources:projectRoots()
	local roots, seen = {}, {}
	local function add(path)
		if path and not seen[path] and self.service.exists(path) then seen[path] = true; table.insert(roots, path) end
	end
	for _, name in ipairs(Builds.roots) do add(self.home .. "/" .. name) end
	for _, path in ipairs(Model.db.folders or {}) do add(path) end
	return roots
end

local function repositoryRoot(service, path, root)
	local current = path
	while current and #current >= #root do
		if service.exists(current .. "/.git") then return current end
		current = current:match("^(.*)/[^/]+$")
	end
	return nil
end

-- Projects: build folders found beside their markers, measured with when
-- they were built and when their sources were last edited. Folders under
-- a megabyte are left out: a `build` folder of source files beside a
-- Makefile is noise, not output.
Sources.buildMinimumBytes = 1e6
function Sources:projects(done)
	local service = self.service
	local roots = self:projectRoots()
	if #roots == 0 then done({}); return end
	local generation = self.generation
	service.command(Projects.findArguments(roots), function(_, output)
		if generation ~= self.generation then return end
		local found = {}
		for path in (output or ""):gmatch("([^\n]+)") do
			if path:sub(1, 1) == "/" then
				local name, parent = path:match("([^/]+)$"), path:match("^(.*)/[^/]+$")
				local root = ""
				for _, candidate in ipairs(roots) do
					if parent:sub(1, #candidate) == candidate and #candidate > #root then root = candidate end
				end
				if root ~= "" and not Projects.isToolFolder(parent, root) then
					local siblings
					for _, rule in ipairs(Projects.rulesFor(name)) do
						local marker
						for _, pattern in ipairs(rule.markers) do
							if pattern:find("*", 1, true) then
								siblings = siblings or service.children(parent)
								for _, sibling in ipairs(siblings) do
									if Projects.markerMatches(pattern, sibling.name) then marker = sibling.path; break end
								end
							elseif service.exists(parent .. "/" .. pattern) then marker = parent .. "/" .. pattern end
							if marker then break end
						end
						if marker then
							local proven = false
							for _, inner in ipairs(rule.inner) do if service.exists(path .. "/" .. inner) then proven = true; break end end
							table.insert(found, {path = path, parent = parent, rule = rule, marker = marker, proven = proven, root = root})
							break
						end
					end
				end
			end
		end
		local buildPaths, projectPaths, projectIndex = {}, {}, {}
		for _, entry in ipairs(found) do
			table.insert(buildPaths, entry.path)
			if not projectIndex[entry.parent] then projectIndex[entry.parent] = #projectPaths + 1; table.insert(projectPaths, entry.parent) end
		end
		local exclusions = {}
		for _, path in ipairs(buildPaths) do table.insert(exclusions, path) end
		-- A project's own sources, not its Git record or the worktrees tools keep inside it.
		for _, path in ipairs(projectPaths) do
			for _, inside in ipairs({"/.git", "/.claude/worktrees", "/.codex"}) do table.insert(exclusions, path .. inside) end
		end
		self:measure(buildPaths, {}, function(built)
			self:measure(projectPaths, exclusions, function(edited)
				local rows, now = {}, os.time()
				for index, entry in ipairs(found) do
					local record, project = built[index] or {}, edited[projectIndex[entry.parent]] or {}
					if (record.bytes or 0) < Sources.buildMinimumBytes then goto continue end
					local facts = Projects.classify({proven = entry.proven, built = record.used, edited = project.used}, now)
					local name = Projects.displayName(entry.parent, repositoryRoot(service, entry.parent, entry.root))
					table.insert(rows, {id = entry.path, path = entry.path, name = entry.rule.name .. " · " .. name, section = "builds",
						owner = entry.rule.owner, what = entry.rule.what, bytes = record.bytes, used = record.used, state = record.state or "measured",
						verdict = facts.verdict, action = "trash", reason = facts.reason, marker = entry.marker, project = entry.parent, edited = project.used})
					::continue::
				end
				done(rows)
			end)
		end)
	end)
end

local WORKTREE_VERDICTS = {candidate = "safe", missing = "safe", primary = "keep", locked = "keep", kept = "keep"}

-- Worktrees: every linked checkout under the project folders and the tools'
-- own worktree roots, with its Git evidence.
function Sources:worktrees(done)
	local generation = self.generation
	self.service.worktreeScan(self:projectRoots(), function(entries, facts)
		if generation ~= self.generation then return end
		local rows, now = {}, os.time()
		for _, row in ipairs(Worktrees.rows(entries, facts, {now = now})) do
			if not entries or row.state ~= "primary" then
				local verdict = WORKTREE_VERDICTS[row.state] or "review"
				local action = row.state == "candidate" and "worktreeRemove" or row.prune and "worktreePrune" or "none"
				table.insert(rows, {id = row.path, path = row.path, name = row.name, section = row.prune and "missing" or "worktrees",
					owner = row.manager or "Git", what = "A linked worktree of " .. (row.repository and (row.repository:match("([^/]+)$") or row.repository) or "a repository") .. " on " .. (row.detached and ("detached " .. (row.head or "")) or (row.branch or "no branch")) .. ".",
					detail = row.roleLabel, bytes = row.bytes, used = row.lastActivity, state = row.worktreeBytes and "measured" or (row.prune and "missing" or "failed"),
					verdict = verdict, action = action, reason = table.concat(row.reasons or {}, " ") .. (#(row.warnings or {}) > 0 and (" " .. table.concat(row.warnings, " ")) or ""),
					repository = row.repository, commonDir = row.commonDir, branch = row.branch, worktreeState = row.state})
			end
		end
		done(rows)
	end)
end

-- Runs every loader in order. Each finished category replaces its rows and
-- redraws; `scan.pending` names the ones still to come.
function Sources:run(categories)
	self:cancel()
	local generation = self.generation
	local scan = Model.db.scan
	scan.generation, scan.running, scan.pending = generation, true, {}
	local list = categories or Sources.order
	for _, id in ipairs(list) do scan.pending[id] = true end
	for _, id in ipairs(list) do
		for _, row in ipairs(Items:inCategory(id)) do row.state = "pending" end
	end
	if self.router.changed then self.router.changed() end
	local function step(index)
		local id = list[index]
		if not id then
			scan.running, scan.status = false, ""
			if self.router.changed then self.router.changed() end
			return
		end
		scan.status = "Measuring " .. self:title(id) .. "…"
		if self.router.changed then self.router.changed() end
		self[id](self, function(rows)
			if generation ~= self.generation then return end
			Items:replace(id, rows)
			scan.pending[id] = nil
			if self.router.refresh then self.router.refresh() end
			step(index + 1)
		end)
	end
	step(1)
end

function Sources:title(id)
	for _, category in ipairs(Categories) do if category.id == id then return category.title end end
	return id
end

function Sources:dispose() self:cancel() end

return Sources
