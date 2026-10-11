local ns = require("AppKit")
local Knowledge = require("apps.diskmap.knowledge.Paths")
local Scanner = require("apps.diskmap.services.Scanner")
local System = {}
-- The person's home folder. Inside the App Sandbox HOME names Diskmap's
-- container, so paths and access checks would all miss.
System.mock = false
System.home = ns.homeDirectory() or os.getenv("HOME") or "/Users"
function System.quote(value)
	assert(type(value) == "string" and not value:find("\0", 1, true), "Invalid path")
	return "'" .. value:gsub("'", "'\\''") .. "'"
end
local function json(value)
	if type(value) == "string" then return '"' .. value:gsub('[%z\1-\31\\"]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
	if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
	if type(value) ~= "table" then return "null" end
	local out = {}
	if #value > 0 then for _, v in ipairs(value) do table.insert(out, (json(v))) end; return "[" .. table.concat(out, ",") .. "]" end
	for k, v in pairs(value) do table.insert(out, json(k) .. ":" .. json(v)) end
	return "{" .. table.concat(out, ",") .. "}"
end
-- Diskmap's folder in Application Support, resolved by NSFileManager once
-- per launch. Everything Diskmap keeps between launches lives there except
-- the operations log, which stays in ~/Library/Logs where Console finds it.
local supportDirectory
function System.supportPath(name)
	supportDirectory = supportDirectory or assert(ns.applicationSupportDirectory("Diskmap"))
	return supportDirectory .. "/" .. name
end
local function readFile(path)
	local file = io.open(path, "r")
	if not file then return nil end
	local body = file:read("*a"); file:close()
	return body
end
local function writeFile(path, body, append)
	local directory = path:match("^(.*)/[^/]+$")
	if not os.execute("/bin/mkdir -p " .. System.quote(directory)) then return false end
	local file = io.open(path, append and "a" or "w")
	if not file then return false end
	file:write(body); file:close()
	return true
end
local function readJson(name, fallback)
	local body = readFile(System.supportPath(name))
	if not body then return fallback end
	local ok, value = pcall(ns.json_parse, body)
	return ok and type(value) == "table" and value or fallback
end
local function writeJson(name, value)
	local path = System.supportPath(name)
	local file = io.open(path .. ".tmp", "w"); if not file then return false end
	file:write(json(value)); file:close()
	return os.rename(path .. ".tmp", path)
end
function System.loadKeep() return readJson("kept.json", {}) end
function System.saveKeep(kept) return writeJson("kept.json", kept) end

local function await(job, completion, progress)
	ns.async(function()
		while not job.cancelled do
			local done, result = Scanner.poll(job)
			if done then if not job.cancelled then completion(result) end; return end
			if result and progress then progress(result) end
			ns.sleep(0.25)
		end
	end)
end
-- Sizes of `paths` in one walk, each with when something inside was last
-- written, its state ("measured", "missing", "unreadable") and its
-- immediate children {name, path, bytes, used, directory}, largest first,
-- the two hundred largest (the rest are summed into `otherBytes`). Returns
-- the job for `cancel`.
function System.measure(paths, exclusions, completion)
	local ok, job = pcall(Scanner.start, paths, exclusions or {}, {treeDepth = 1, treeMinimumBytes = 0})
	if not ok then completion({}, tostring(job)); return nil end
	await(job, function(result)
		local records = {}
		for index, path in ipairs(paths) do
			local tree, folder, state = result.trees and result.trees[index], result.folders and result.folders[index], result.rootStates and result.rootStates[index]
			-- A root with folders macOS protects inside it is still measured: its
			-- size is a lower bound (`partial`). Denied is a root nothing could be read of.
			local record = {bytes = tree and math.floor((tree.kb or 0) * 1024 + 0.5) or 0, used = folder and folder.used and math.floor(folder.used) or nil,
				partial = tree and tree.partial == true, children = {}, otherBytes = folder and math.floor((folder.otherKb or 0) * 1024 + 0.5) or 0, otherCount = folder and folder.otherCount or 0}
			if state == "missing" then record.state = "missing"
			elseif state == "measured" or record.bytes > 0 then record.state = "measured"
			elseif state == "unreadable" then record.state = "denied"
			else record.state = "failed" end
			for _, child in ipairs(folder and folder.children or {}) do
				if child.name and child.name ~= "" then
					table.insert(record.children, {name = child.name, path = path .. "/" .. child.name, bytes = math.floor((child.kb or 0) * 1024 + 0.5),
						used = child.used and math.floor(child.used) or nil, directory = child.directory == true})
				end
			end
			records[index] = record
		end
		completion(records)
	end)
	return job
end
System.cancel = Scanner.cancel
-- Everything under `path` as one tree of its largest folders and files
-- (`treeDepth` in src/plugins/storage/README.md): what the Folder Map
-- lists. The startup disk's files live on its Data volume, so "/" is
-- measured through it and reported under the paths people know.
function System.scanFolder(path, options, completion, progress)
	local root, scanOptions = path, {}
	for key, value in pairs(options or {}) do scanOptions[key] = value end
	if path == "/" then root, scanOptions.logicalRoots = Knowledge.startupData, {[Knowledge.startupData] = "/"} end
	local ok, job = pcall(Scanner.start, {root}, {}, scanOptions)
	if not ok then completion(nil, tostring(job), {errors = 0, visited = 0}); return nil end
	ns.async(function()
		while not job.cancelled do
			local done, result = Scanner.poll(job)
			if done then
				if job.cancelled then return end
				local failure = result.failure ~= "" and result.failure or nil
				local folder = result.folders and result.folders[1]
				if not folder and not failure then failure = "The folder could not be read." end
				completion(folder, failure, {errors = result.errors or 0, visited = result.visited or 0})
				return
			end
			if progress then progress(Scanner.progress(job) or 0) end
			ns.sleep(0.25)
		end
	end)
	return job
end
System.cancelFolderScan = Scanner.cancel

function System.command(argv, completion)
	local job = Scanner.commandStart(argv)
	ns.async(function()
		while true do
			local done, result = Scanner.commandPoll(job)
			if done then completion(result.ok, result.output); return end
			ns.sleep(0.1)
		end
	end)
end
local function lines(output)
	local result = {}
	for line in (output or ""):gmatch("([^\n]+)") do
		line = line:gsub("\r$", "")
		if line ~= "" then table.insert(result, line) end
	end
	return result
end
local function expand(path)
	if path == "~" then return System.home end
	if type(path) == "string" and path:sub(1, 2) == "~/" then return System.home .. path:sub(2) end
	return path
end
-- A folder's entries, names only; dot-files included.
function System.children(path)
	local rows = {}
	for _, entry in ipairs(ns.readDirectory(expand(path), 0) or {}) do
		table.insert(rows, {name = entry.name, path = entry.path, directory = entry.directory == true})
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end
function System.readPropertyList(path) return ns.readPropertyList(expand(path)) end
function System.exists(path)
	local file = io.open(expand(path), "r")
	if file then file:close(); return true end
	return false
end
-- The account's TMPDIR, as `getconf DARWIN_USER_TEMP_DIR` names it.
function System.tmpdir()
	local dir = os.getenv("TMPDIR") or ""
	return (dir:gsub("/+$", ""))
end
-- Whether Diskmap has Full Disk Access. The TCC database is readable only
-- with it, and trying to open it never asks the person.
function System.hasFullDiskAccess()
	local file = io.open(System.home .. "/Library/Application Support/com.apple.TCC/TCC.db", "rb")
	if file then file:close(); return true end
	return false
end
-- CoreSimulator's live state is authoritative for availability and whether
-- a device is running. A device folder alone cannot establish either.
function System.simulatorDevices(completion)
	System.command({"/usr/bin/xcrun", "simctl", "list", "devices", "-j"}, function(ok, output)
		local parsed, value = pcall(ns.json_parse, type(output) == "string" and output or "")
		if ok and parsed and type(value) == "table" and type(value.devices) == "table" then completion(value)
		else completion(nil, "Device state could not be read. Retry, or open Xcode to manage devices.") end
	end)
end
-- Installed simulator runtimes with their sizes, keyed by image UUID.
function System.simulatorRuntimes(completion)
	System.command({"/usr/bin/xcrun", "simctl", "runtime", "list", "-j"}, function(ok, output)
		local parsed, value = pcall(ns.json_parse, type(output) == "string" and output or "")
		if ok and parsed and type(value) == "table" then completion(value)
		else completion(nil, "Runtimes could not be read. Retry, or manage them in Xcode › Settings › Components.") end
	end)
end
-- Every application bundle Spotlight has indexed, as {path, bundleId, name,
-- team, groups}: what claims a Library folder. Completes with nil when
-- Spotlight is unavailable.
function System.installedApplications(completion)
	System.command({"/usr/bin/mdfind", "kMDItemContentType == 'com.apple.application-bundle'"}, function(ok, output)
		if not ok then completion(nil); return end
		local paths = lines(output)
		if #paths == 0 then completion(nil); return end
		local argv = {"/usr/bin/mdls", "-raw", "-name", "kMDItemCFBundleIdentifier", "-name", "kMDItemDisplayName"}
		for _, path in ipairs(paths) do table.insert(argv, path) end
		System.command(argv, function(listed, values)
			if not listed then completion(nil); return end
			local apps = require("apps.diskmap.helpers.Leftovers").parseApplications(values, paths)
			ns.codeSignatures(paths, function(signatures)
				for _, app in ipairs(apps) do
					local signature = signatures[app.path]
					if signature then app.team, app.groups = signature.team, signature.groups end
				end
				completion(apps)
			end)
		end)
	end)
end
-- The startup container's APFS volumes with their own used space, from
-- `diskutil apfs list -plist`: {name, role, bytes}. Preboot and swap are
-- measured by volume, since adding their files up counts clones twice.
function System.volumes(completion)
	System.command({"/usr/sbin/diskutil", "info", "-plist", "/"}, function(ok, infoText)
		local info = ok and ns.parsePropertyList(infoText) or nil
		System.command({"/usr/sbin/diskutil", "apfs", "list", "-plist"}, function(listed, listText)
			local plist = listed and ns.parsePropertyList(listText) or nil
			completion(require("apps.diskmap.helpers.Volumes").parse(plist, info and info.APFSContainerReference))
		end)
	end)
end
-- What a cleanup checks just before each move (helpers/Verify.lua).
System.fileIdentity = ns.fileIdentity
function System.cleanupProbes()
	local running = {}
	for _, id in ipairs(ns.runningApplications() or {}) do running[id] = true end
	-- Existence is lstat, never an open: opening another app's container
	-- would make macOS ask for access to other apps' data.
	return {running = running, appPath = ns.applicationPath, identity = ns.fileIdentity,
		exists = function(path) return ns.fileIdentity(path) ~= nil end}
end
function System.trash(path)
	local current = ""
	for part in path:gmatch("[^/]+") do
		current = current .. "/" .. part
		if os.execute("test -L " .. System.quote(current)) then return false, "This location contains a symbolic link. Review it in Finder instead." end
	end
	return ns.moveToTrash(path)
end
System.reveal = ns.revealInFinder
System.diskSpace = ns.diskSpace
function System.volumeCapacity(path) return ns.volumeCapacity(path or "/") end
function System.quickLook(paths, index) ns.quickLook(paths, index) end
function System.copy(text) ns.copyToClipboard(text) end
function System.onOpenFiles(handler) ns.onOpenFiles(handler) end
function System.pickFolder(title) return ns.pickFolder(title) end
function System.openSettings(section)
	local targets = {
		privacy = "com.apple.preference.security?Privacy_AllFiles",
		siri = "com.apple.Siri-Settings.extension",
		intelligence = "com.apple.Siri-Settings.extension",
		dictation = "com.apple.Keyboard-Settings.extension",
		voices = "com.apple.Accessibility-Settings.extension",
		softwareupdate = "com.apple.Software-Update-Settings.extension",
	}
	local target = "x-apple.systempreferences:" .. (targets[section] or "com.apple.settings.Storage")
	os.execute("/usr/bin/open " .. System.quote(target))
end
function System.confirmAction(title, message, parent)
	return ns.Alert {parent = parent, title = title, message = message, buttons = {"Cancel", title}} == 2
end
function System.showError(title, message, parent) ns.Alert {parent = parent, title = title, message = message} end
System.decode = ns.json_parse
-- Folder lists the person chose ("projects"): one "path<TAB>bookmark" line
-- each. The security-scoped bookmark follows a moved or renamed folder and
-- keeps access should Diskmap run sandboxed.
function System.loadFolders(name)
	local roots = {}
	for line in (readFile(System.supportPath(name .. "-folders")) or ""):gmatch("[^\n]+") do
		local path, bookmark = line:match("^([^\t]*)\t?(.*)$")
		local resolved = bookmark ~= "" and ns.resolveBookmark(bookmark)
		table.insert(roots, resolved or path)
	end
	return roots
end
function System.saveFolders(name, roots)
	local list = {}
	for _, path in ipairs(roots) do table.insert(list, path .. "\t" .. (ns.bookmark(path) or "")) end
	return writeFile(System.supportPath(name .. "-folders"), table.concat(list, "\n"))
end
-- Actions are appended to a plain text log that Console can open too.
local LOG = (os.getenv("HOME") or "") .. "/Library/Logs/Diskmap/operations.log"
function System.logOperation(line) return writeFile(LOG, line .. "\n", true) end
function System.operationLog() return lines(readFile(LOG)) end
-- Leftover Git worktrees: every repository under the project folders and the
-- tools' own worktree roots, with each worktree's evidence.
local function measureSizes(paths, completion)
	System.measure(paths, {}, function(records)
		local sizes = {}
		for index in ipairs(paths) do sizes[index] = records[index] and records[index].bytes or 0 end
		completion(sizes)
	end)
end
function System.worktreeScan(roots, completion, progress)
	local Service = require("apps.diskmap.services.Worktrees")
	local searched = {}
	for _, root in ipairs(roots or {}) do table.insert(searched, root) end
	for _, root in ipairs({System.home .. "/.codex/worktrees", System.home .. "/.claude"}) do table.insert(searched, root) end
	local existing = {}
	for _, root in ipairs(searched) do if System.exists(root) then table.insert(existing, root) end end
	if #existing == 0 then completion({}, {}); return end
	Service.repositories(System.command, existing, function(repos)
		Service.list(System.command, repos, function(entries)
			if progress then progress(0, #entries) end
			Service.allFacts(System.command, measureSizes, entries, function(facts) completion(entries, facts) end, progress)
		end)
	end)
end
-- One worktree's current record and evidence, read just before its removal.
function System.worktreeState(row, completion)
	local Service = require("apps.diskmap.services.Worktrees")
	Service.list(System.command, {{path = row.repository, commonDir = row.commonDir}}, function(entries)
		for _, entry in ipairs(entries) do
			if entry.path == row.path then
				Service.facts(System.command, measureSizes, entry, function(facts) completion(entry, facts) end)
				return
			end
		end
		completion(nil, nil)
	end)
end
return System
