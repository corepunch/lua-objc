local ns = require("AppKit")
local Contract = require("apps.diskmap.services.Contract")
local Disk = require("apps.diskmap.services.FixtureDisk")
local Worktrees = require("apps.diskmap.services.Worktrees")
local Builds = require("apps.diskmap.knowledge.Builds")

-- The service over a synthetic Mac (services/FixtureDisk.lua): every
-- member of the contract answered from plain tables, so pages, flows and
-- tests run without a disk, simctl or git. Trash, erase and worktree
-- removal change the tables, so what a cleanup frees can be asserted.
-- Completions run at once.
local Fixture = {}; Fixture.__index = Fixture

local function within(path, root)
	if path == root then return true end
	if root == "/" then return path:sub(1, 1) == "/" end
	return path:sub(1, #root + 1) == root .. "/"
end

function Fixture.new(options)
	options = options or {}
	local home = options.home or "/Users/appleseed"
	local disk = Disk(home)
	local self = setmetatable({home = home, mock = true, label = disk.label, badge = not options.showcase and "Showcase" or false,
		disk = disk, files = disk.files, plists = disk.plists, repos = disk.repos, simulators = disk.simulators,
		kept = {}, folders = {}, log = {}, running = {}, confirm = true, errors = {}, revealed = {}, opened = {}, calls = {}}, Fixture)
	-- Every member is callable as `service.name(...)`, as pages call it.
	local bound = {}
	for name in pairs(Contract.members) do
		bound[name] = function(...) return Fixture[name](self, ...) end
	end
	for key, value in pairs(self) do bound[key] = value end
	bound.fixture = self
	return Contract.check(bound)
end

-- Entries under `path` (not below any of `exclusions`).
function Fixture:under(path, exclusions)
	local found = {}
	for _, entry in ipairs(self.files) do
		if within(entry.path, path) then
			local excluded = false
			for _, exclusion in ipairs(exclusions or {}) do
				if exclusion ~= path and within(entry.path, exclusion) then excluded = true; break end
			end
			if not excluded then table.insert(found, entry) end
		end
	end
	return found
end

function Fixture:exists(path)
	if self.plists[path] then return true end
	for _, entry in ipairs(self.files) do if within(entry.path, path) then return true end end
	for key in pairs(self.plists) do if within(key, path) then return true end end
	return false
end

-- The immediate children of `path` with their sizes and dates.
function Fixture:childrenOf(path, exclusions)
	local map, order = {}, {}
	local function add(name, bytes, used, directory)
		local child = map[name]
		if not child then
			child = {name = name, path = path == "/" and ("/" .. name) or (path .. "/" .. name), bytes = 0, used = 0, directory = false}
			map[name] = child; table.insert(order, child)
		end
		child.bytes = child.bytes + bytes
		child.used = math.max(child.used, used or 0)
		child.directory = child.directory or directory
	end
	for _, entry in ipairs(self:under(path, exclusions)) do
		local rest = entry.path:sub(#path + (path == "/" and 1 or 2))
		local name = rest:match("^([^/]+)")
		if name then add(name, entry.bytes, entry.used, rest:find("/", 1, true) ~= nil) end
	end
	for key in pairs(self.plists) do
		if within(key, path) and key ~= path then
			local rest = key:sub(#path + 2)
			local name = rest:match("^([^/]+)")
			if name then add(name, 0, 0, rest:find("/", 1, true) ~= nil) end
		end
	end
	table.sort(order, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.name < b.name end)
	return order
end

function Fixture:measure(paths, exclusions, completion)
	local records = {}
	for index, path in ipairs(paths) do
		local entries = self:under(path, exclusions)
		local bytes, used = 0, nil
		for _, entry in ipairs(entries) do bytes = bytes + entry.bytes; used = math.max(used or 0, entry.used) end
		local present = #entries > 0 or self:exists(path)
		records[index] = {bytes = bytes, used = used, state = present and "measured" or "missing", children = {}, otherBytes = 0, otherCount = 0}
		if present then
			for _, child in ipairs(self:childrenOf(path, exclusions)) do
				table.insert(records[index].children, {name = child.name, path = child.path, bytes = child.bytes, used = child.used > 0 and child.used or nil, directory = child.directory})
			end
		end
	end
	completion(records)
	return {}
end
function Fixture:cancel() end

-- The folder tree the Folder Map lists, as the scanner shapes it.
function Fixture:scanFolder(path, options, completion)
	if not self:exists(path) then completion(nil, "The folder could not be read.", {errors = 0, visited = 0}); return nil end
	local depth, minimum = (options or {}).treeDepth or 8, (options or {}).treeMinimumBytes or 0
	local visited = 0
	local function node(folder, level)
		local entries = self:under(folder)
		local bytes, used = 0, 0
		for _, entry in ipairs(entries) do bytes = bytes + entry.bytes; used = math.max(used, entry.used) end
		local result = {name = folder:match("([^/]+)$") or folder, kb = bytes / 1024, used = used, directory = true}
		if level > depth then result.deeper = true; return result end
		result.children, result.otherKb, result.otherCount = {}, 0, 0
		for _, child in ipairs(self:childrenOf(folder)) do
			visited = visited + 1
			if child.bytes < minimum then result.otherKb, result.otherCount = result.otherKb + child.bytes / 1024, result.otherCount + 1
			elseif child.directory then table.insert(result.children, node(child.path, level + 1))
			else table.insert(result.children, {name = child.name, kb = child.bytes / 1024, used = child.used, directory = false}) end
		end
		return result
	end
	completion(node(path, 1), nil, {errors = 0, visited = visited})
	return {}
end
function Fixture:cancelFolderScan() end

function Fixture:children(path)
	local rows = {}
	for _, child in ipairs(self:childrenOf(path)) do table.insert(rows, {name = child.name, path = child.path, directory = child.directory}) end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end
function Fixture:readPropertyList(path) return self.plists[path] end
function Fixture:tmpdir() return self.disk.tmpdir end
function Fixture:hasFullDiskAccess() return true end
function Fixture:simulatorDevices(completion)
	local copy = {devices = {}}
	for runtime, list in pairs(self.simulators.devices) do
		copy.devices[runtime] = {}
		for _, device in ipairs(list) do
			local record = {}
			for key, value in pairs(device) do record[key] = value end
			table.insert(copy.devices[runtime], record)
		end
	end
	completion(copy)
end
function Fixture:simulatorRuntimes(completion)
	local copy = {}
	for key, runtime in pairs(self.simulators.runtimes) do
		copy[key] = {}
		for field, value in pairs(runtime) do copy[key][field] = value end
	end
	completion(copy)
end
function Fixture:installedApplications(completion) completion(self.disk.apps) end
function Fixture:volumes(completion) completion(self.disk.volumes) end

-- Bytes the fixture's files hold, so free space follows removals.
function Fixture:usedBytes()
	local total = self.disk.otherBytes
	for _, entry in ipairs(self.files) do total = total + entry.bytes end
	return total
end
function Fixture:diskSpace()
	local total = self.disk.capacityBytes
	return {totalKb = total / 1024, freeKb = (total - self:usedBytes()) / 1024}
end
function Fixture:volumeCapacity()
	local total = self.disk.capacityBytes
	return {total = total, available = total - self:usedBytes()}
end

-- Removes everything under `path`; returns the bytes it held.
function Fixture:removeUnder(path)
	local kept, removed = {}, 0
	for _, entry in ipairs(self.files) do
		if within(entry.path, path) then removed = removed + entry.bytes else table.insert(kept, entry) end
	end
	self.files = kept
	for key in pairs(self.plists) do if within(key, path) then self.plists[key] = nil end end
	return removed
end
function Fixture:trash(path)
	if not self:exists(path) then return false, "No such item." end
	self:removeUnder(path)
	return true
end
local function hash(path)
	local value = 7
	for index = 1, #path do value = (value * 31 + path:byte(index)) % 2147483647 end
	return value
end
function Fixture:fileIdentity(path)
	if not self:exists(path) then return nil end
	return {inode = hash(path), device = 1, symlink = false}
end
function Fixture:cleanupProbes()
	local running = {}
	for id in pairs(self.running) do running[id] = true end
	return {running = running, appPath = function(id) for _, app in ipairs(self.disk.apps) do if app.bundleId == id then return app.path end end end,
		identity = function(path) return self:fileIdentity(path) end, exists = function(path) return self:exists(path) end}
end

-- Commands: the subset of simctl, git, find, test and stat the sources use.
function Fixture:command(argv, completion)
	table.insert(self.calls, argv)
	local tool = argv[1]
	if tool == "/usr/bin/xcrun" and argv[2] == "simctl" then return self:simctl(argv, completion) end
	if tool == "/usr/bin/git" then return self:git(argv, completion) end
	if tool == "/usr/bin/find" then return self:find(argv, completion) end
	if tool == "/bin/test" then completion(self:exists(argv[3]), ""); return end
	if tool == "/usr/bin/stat" then
		local times = {}
		for index = 4, #argv do
			local path, used = argv[index], 0
			for _, entry in ipairs(self:under(path)) do used = math.max(used, entry.used) end
			if used > 0 then table.insert(times, tostring(used)) end
		end
		completion(#times > 0, table.concat(times, "\n"))
		return
	end
	completion(false, "The fixture never runs " .. tostring(tool) .. ".")
end

function Fixture:simctl(argv, completion)
	local action, id = argv[3], argv[4]
	if action == "runtime" and argv[4] == "delete" then
		local runtime = self.simulators.runtimes[argv[5]]
		if not runtime or runtime.deletable ~= true then completion(false, "Runtime is not deletable."); return end
		self.simulators.runtimes[argv[5]] = nil
		for _, device in ipairs(self.simulators.devices[runtime.runtimeIdentifier] or {}) do device.isAvailable = false end
		completion(true, "")
		return
	end
	if action ~= "erase" and action ~= "delete" then completion(false, "Unsupported simctl command."); return end
	for runtime, list in pairs(self.simulators.devices) do
		for index, device in ipairs(list) do
			if device.udid == id then
				if device.state ~= "Shutdown" then completion(false, "Unable to " .. action .. " a running device."); return end
				local root = self.home .. "/Library/Developer/CoreSimulator/Devices/" .. id
				if action == "erase" then self:removeUnder(root .. "/data") else self:removeUnder(root); table.remove(list, index) end
				completion(true, "")
				return
			end
		end
	end
	-- A folder simctl no longer lists can still be deleted by UDID.
	local root = self.home .. "/Library/Developer/CoreSimulator/Devices/" .. tostring(id)
	if action == "delete" and self:exists(root) then self:removeUnder(root); completion(true, ""); return end
	completion(false, "Invalid device: " .. tostring(id))
end

local function repoOf(self, checkout)
	for path, repo in pairs(self.repos) do
		if path == checkout then return repo, nil end
		for _, worktree in ipairs(repo.worktrees) do if worktree.path == checkout then return repo, worktree end end
	end
end

function Fixture:git(argv, completion)
	local checkout = argv[3]
	local repo, worktree = repoOf(self, checkout)
	if not repo then completion(false, "fatal: not a git repository: " .. tostring(checkout)); return end
	local command = argv[4]
	if command == "rev-parse" and argv[5] == "--path-format=absolute" then completion(true, repo.commonDir .. "\n"); return end
	if command == "rev-parse" and argv[5] == "--absolute-git-dir" then
		completion(true, (worktree and (repo.commonDir .. "/worktrees/" .. worktree.path:match("([^/]+)$")) or repo.commonDir) .. "\n"); return
	end
	if command == "rev-parse" and argv[5] == "--verify" then completion(true, "aaaa1111\n"); return end
	if command == "worktree" and argv[5] == "list" then
		local fields = {"worktree " .. (({next(self.repos)})[1] and "" or "") .. ""}
		local out = {}
		local function record(path, head, branch, detached, prunable)
			table.insert(out, "worktree " .. path); table.insert(out, "HEAD " .. head)
			if detached then table.insert(out, "detached") elseif branch then table.insert(out, "branch refs/heads/" .. branch) end
			if prunable then table.insert(out, "prunable gitdir file points to non-existent location") end
			table.insert(out, "")
		end
		local repoPath
		for path, candidate in pairs(self.repos) do if candidate == repo then repoPath = path end end
		record(repoPath, repo.head, repo.branch)
		for _, entry in ipairs(repo.worktrees) do record(entry.path, entry.head, entry.branch, entry.detached, entry.prunable) end
		completion(true, table.concat(out, "\0") .. "\0")
		return
	end
	if command == "worktree" and argv[5] == "remove" then
		for index, entry in ipairs(repo.worktrees) do
			if entry.path == argv[6] then
				if entry.facts and ((entry.facts.changes or 0) > 0 or (entry.facts.untracked or 0) > 0) then completion(false, "fatal: '" .. entry.path .. "' contains modified or untracked files, use --force to delete it"); return end
				self:removeUnder(entry.path)
				table.remove(repo.worktrees, index)
				completion(true, ""); return
			end
		end
		completion(false, "fatal: '" .. tostring(argv[6]) .. "' is not a working tree"); return
	end
	if command == "worktree" and argv[5] == "prune" then
		for index = #repo.worktrees, 1, -1 do if repo.worktrees[index].prunable then table.remove(repo.worktrees, index) end end
		completion(true, ""); return
	end
	local facts = worktree and worktree.facts or {}
	if command == "status" then
		local records = {}
		for _ = 1, facts.changes or 0 do table.insert(records, " M src/index.ts") end
		for _ = 1, facts.untracked or 0 do table.insert(records, "?? notes.txt") end
		completion(true, #records > 0 and (table.concat(records, "\0") .. "\0") or ""); return
	end
	if command == "rev-list" then completion(true, tostring(facts.unpublished or 0) .. "\n"); return end
	if command == "symbolic-ref" then completion(true, "origin/main\n"); return end
	if command == "merge-base" then completion(facts.merged == true, ""); return end
	if command == "submodule" then completion(true, ""); return end
	if command == "ls-files" then completion(true, ""); return end
	completion(false, "The fixture does not run git " .. tostring(command) .. ".")
end

-- `find`: build folders under roots by name (helpers/Projects), or `.git`
-- entries for the repository search (services/Worktrees).
function Fixture:find(argv, completion)
	local roots, names, wantGit = {}, {}, false
	local index = 2
	while argv[index] and argv[index]:sub(1, 1) == "/" do table.insert(roots, argv[index]); index = index + 1 end
	for position = index, #argv do
		if argv[position] == "-name" then
			local name = argv[position + 1]
			if name == ".git" then wantGit = true else names[name] = true end
		end
	end
	local skip = {}
	for _, name in ipairs(Builds.skip) do skip[name] = true end
	local out, seen = {}, {}
	local function emit(path) if not seen[path] then seen[path] = true; table.insert(out, path) end end
	local function walk(folder, depth)
		if depth > Builds.depth then return end
		for _, child in ipairs(self:childrenOf(folder)) do
			if wantGit and child.name == ".git" then emit(child.path)
			elseif child.directory then
				if names[child.name] then emit(child.path)
				elseif not skip[child.name] and child.name ~= ".git" then walk(child.path, depth + 1) end
			end
		end
	end
	for _, root in ipairs(roots) do if self:exists(root) then walk(root, 1) end end
	completion(true, table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

local function sizes(self)
	return function(paths, completion)
		local result = {}
		for index, path in ipairs(paths) do
			local bytes = 0
			for _, entry in ipairs(self:under(path)) do bytes = bytes + entry.bytes end
			result[index] = bytes
		end
		completion(result)
	end
end
function Fixture:worktreeScan(roots, completion, progress)
	local run = function(argv, done) self:command(argv, done) end
	local searched = {}
	for _, root in ipairs(roots or {}) do table.insert(searched, root) end
	table.insert(searched, self.home .. "/.codex/worktrees")
	Worktrees.repositories(run, searched, function(repos)
		Worktrees.list(run, repos, function(entries)
			Worktrees.allFacts(run, sizes(self), entries, function(facts)
				-- Activity comes from the fixture's own dates.
				for _, entry in ipairs(entries) do
					local _, worktree = repoOf(self, entry.path)
					if worktree and worktree.facts and facts[entry.path] then facts[entry.path].lastActivity = worktree.facts.activity end
				end
				completion(entries, facts)
			end, progress)
		end)
	end)
end
function Fixture:worktreeState(row, completion)
	local run = function(argv, done) self:command(argv, done) end
	Worktrees.list(run, {{path = row.repository, commonDir = row.commonDir}}, function(entries)
		for _, entry in ipairs(entries) do
			if entry.path == row.path then
				Worktrees.facts(run, sizes(self), entry, function(facts)
					local _, worktree = repoOf(self, entry.path)
					if worktree and worktree.facts then facts.lastActivity = worktree.facts.activity end
					completion(entry, facts)
				end)
				return
			end
		end
		completion(nil, nil)
	end)
end

function Fixture:loadKeep() return self.kept end
function Fixture:saveKeep(kept) self.kept = kept; return true end
function Fixture:loadFolders(name) return self.folders[name] or {} end
function Fixture:saveFolders(name, roots) self.folders[name] = roots; return true end
function Fixture:logOperation(line) table.insert(self.log, line); return true end
function Fixture:operationLog() return self.log end
function Fixture:confirmAction() return self.confirm == true end
function Fixture:showError(title, message) table.insert(self.errors, {title = title, message = message}) end
function Fixture:reveal(path) table.insert(self.revealed, path) end
function Fixture:quickLook() end
function Fixture:copy(text) self.copied = text end
function Fixture:openSettings(section) table.insert(self.opened, section or "storage") end
function Fixture:onOpenFiles() end
function Fixture:pickFolder() return nil end
function Fixture:decode(value) return ns.json_parse(value) end

return Fixture
