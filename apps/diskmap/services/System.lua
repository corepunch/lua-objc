local Locations = require("apps.diskmap.models.Locations")
local ns = require("AppKit")
local Knowledge = require("apps.diskmap.knowledge.Paths")
local Owners = require("apps.diskmap.services.Owners")
local System = {}
-- The person's home folder. Inside the App Sandbox HOME names Diskmap's
-- container, so catalog paths and access checks would all miss.
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
local function readJson(name, fallback)
	local f = io.open(System.supportPath(name), "r")
	if not f then return fallback end
	local body = f:read("*a"); f:close()
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
-- Watched locations: resources by id, folders by path plus a bookmark that
-- follows the folder when it is moved or renamed.
function System.loadWatchlist()
	local entries = readJson("watchlist.json", {})
	for _, entry in ipairs(entries) do
		if entry.kind == "folder" and type(entry.bookmark) == "string" and entry.bookmark ~= "" then
			entry.path = ns.resolveBookmark(entry.bookmark) or entry.path
		end
	end
	return entries
end
function System.saveWatchlist(entries)
	local stored = {}
	for _, entry in ipairs(entries) do
		local copy = {}
		for key, value in pairs(entry) do copy[key] = value end
		if copy.kind == "folder" then copy.bookmark = ns.bookmark(copy.path) end
		table.insert(stored, copy)
	end
	return writeJson("watchlist.json", stored)
end
local Scanner = require("apps.diskmap.services.Scanner")
System.start = Scanner.start
System.cancel = Scanner.cancel
System.poll = Scanner.poll
function System.await(job, completion, progress)
	ns.async(function()
		while not job.cancelled do
			local done, result = System.poll(job)
			if done then completion(result); return end
			if result and progress then progress(result) end
			ns.sleep(0.25)
		end
	end)
end
function System.exportMockSnapshot(outputPath, completion)
	local disk = ns.diskSpace("/")
	if not disk then completion({failure = "Could not read internal disk capacity."}); return end
	local ok, job = pcall(Scanner.startExport, Knowledge.snapshotRoots, Knowledge.scanExclusions, outputPath, {
		capacityBytes = disk.totalKb * 1024,
		availableBytes = disk.freeKb * 1024,
		logicalRoots = { [Knowledge.startupData] = "/" },
	})
	if not ok then completion({failure = tostring(job)}); return end
	System.await(job, completion)
end
function System.loadSettings()
	local file = io.open(System.supportPath("background"), "r")
	if not file then return true end
	local value = file:read("*l"); file:close()
	return value ~= "paused"
end
function System.saveSettings(enabled)
	local file = io.open(System.supportPath("background"), "w")
	if not file then return false end
	file:write(enabled and "enabled" or "paused"); file:close()
	return true
end
function System.monitor(visible, refresh)
	ns.async(function()
		local ticks = 0
		while visible() do
			ns.sleep(30); ticks = ticks + 1
			if visible() and ticks % 30 == 0 then refresh() end
		end
	end)
end
function System.openSettings(section)
	local targets = {
		privacy = "com.apple.preference.security?Privacy_AllFiles",
		siri = "com.apple.Siri-Settings.extension",
		dictation = "com.apple.Keyboard-Settings.extension",
		voices = "com.apple.Accessibility-Settings.extension",
		softwareupdate = "com.apple.Software-Update-Settings.extension",
		timemachine = "com.apple.Time-Machine-Settings.extension",
		spotlight = "com.apple.Spotlight-Settings.extension",
		wallpaper = "com.apple.Wallpaper-Settings.extension",
	}
	local target = "x-apple.systempreferences:" .. (targets[section] or "com.apple.settings.Storage")
	os.execute("/usr/bin/open " .. System.quote(target))
end
function System.openOwner(owner)
	return Owners.open(owner, function(identifier)
		return os.execute("/usr/bin/open -b " .. System.quote(identifier) .. " 2>/dev/null")
	end)
end
function System.confirmTrash(row)
	return ns.Alert {title = "Move " .. row.name .. " to Trash?", message = row.path .. "\n\n" .. row.consequence, buttons = {"Cancel", "Move to Trash"}} == 2
end
function System.confirmEmptyTrash(row, size)
	return ns.Alert {title = "Permanently empty Trash?", message = "This permanently removes " .. size .. " of files in Trash on all mounted volumes. This cannot be undone.", buttons = {"Cancel", "Empty Trash"}} == 2
end
function System.confirmOwnerCleanup(row, size)
	return ns.Alert {title = "Clear " .. row.name .. "?", message = "Measured location: " .. row.path .. "\nMeasured allocation: " .. size .. "\n\n" .. (row.consequence or "The owning tool will clear its cache."), buttons = {"Cancel", "Clear Cache"}} == 2
end
function System.runOwnerCleanup(commandId, home, completion)
	local commands = {
		["npm-cache"] = {"/usr/bin/env", "npm", "cache", "clean", "--force", "--cache", home .. "/.npm"},
		["pip-cache"] = {"/usr/bin/env", "python3", "-m", "pip", "--cache-dir", home .. "/Library/Caches/pip", "cache", "purge"},
		["xcode-previews"] = {"/usr/bin/xcrun", "simctl", "--set", "previews", "delete", "all"},
	}
	local argv = commands[commandId]
	if not argv then completion(false, "Unsupported package-manager cache operation."); return end
	System.command(argv, completion)
end
function System.emptyTrash()
	return os.execute("/usr/bin/osascript -e 'tell application \"Finder\" to empty trash'")
end
function System.showError(title, message) ns.Alert {title = title, message = message} end
function System.relaunch(onFailure) ns.relaunch(onFailure) end
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
System.reveal = ns.revealInFinder
System.diskSpace = ns.diskSpace
function System.trash(path)
	local current = ""
	for part in path:gmatch("[^/]+") do
		current = current .. "/" .. part
		local linked = os.execute("test -L " .. System.quote(current))
		if linked then return false, "This location contains a symbolic link. Review it in Finder instead." end
	end
	return ns.moveToTrash(path)
end
function System.agentEntries(model)
	local entries = {}
	for _, id in ipairs({"codex", "opencode", "grok", "claude"}) do
		local root = Locations:find(id .. "-other")
		for _, entry in ipairs(root and ns.readDirectory(root.path, 0) or {}) do
			entry.agent = id; table.insert(entries, entry)
		end
	end
	return entries
end
local function hexId(path)
	return "discovered-" .. path:gsub(".", function(character) return string.format("%02x", character:byte()) end)
end
local function lines(output)
	local result = {}
	for path in (output or ""):gmatch("([^\n]+)") do
		path = path:gsub("\r$", "")
		if path ~= "" then table.insert(result, path) end
	end
	return result
end
local function expand(path)
	local home = System.home
	if path == "~" then return home end
	if type(path) == "string" and path:sub(1, 2) == "~/" then return home .. path:sub(2) end
	return path
end
function System.children(path)
	local listed = ns.readDirectory(expand(path), 0) or {}
	local rows = {}
	for _, entry in ipairs(listed) do
		if entry.directory then table.insert(rows, {name = entry.name, path = entry.path}) end
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end
function System.bundles(root, kind)
	if kind ~= "sdk" then return {} end
	root = expand(root)
	local rows = {}
	local function add(directory)
		local listed = ns.readDirectory(directory, 0)
		if not listed then return end
		for _, entry in ipairs(listed) do
			if entry.directory and entry.name:match("%.sdk$") then
				table.insert(rows, {name = entry.name:gsub("%.sdk$", ""), path = entry.path})
			end
		end
	end
	add(root .. "/SDKs")
	for _, platform in ipairs(ns.readDirectory(root .. "/Contents/Developer/Platforms", 0) or {}) do
		if platform.directory then add(platform.path .. "/Developer/SDKs") end
	end
	return rows
end
function System.readPropertyList(path)
	return ns.readPropertyList(expand(path))
end
-- Sizes of `paths`, and each one's scan state ("measured", "unreadable",
-- "missing"), in the same order.
function System.measure(paths, completion)
	local job = Scanner.start(paths, {})
	System.await(job, function(result)
		local sizes = {}
		for index, tree in ipairs(result.trees or {}) do
			sizes[index] = tree and math.floor((tree.kb or 0) * 1024 + 0.5) or 0
		end
		completion(sizes, result.rootStates)
	end)
end
-- Whether Diskmap has Full Disk Access. The TCC database is readable only
-- with it, and trying to open it never asks the person, unlike opening a
-- protected folder such as Documents.
function System.hasFullDiskAccess()
	local file = io.open(System.home .. "/Library/Application Support/com.apple.TCC/TCC.db", "rb")
	if file then file:close(); return true end
	return false
end
-- The locations no app can read (knowledge/Filesystem) present on this Mac. A protected folder
-- refuses to open with "Operation not permitted" or "Permission denied"; an
-- absent one reports that there is no such file.
function System.protectedLocations()
	local found = {}
	for _, location in ipairs(require("apps.diskmap.knowledge.Filesystem").protected()) do
		local file, message = io.open(location.path, "r")
		if file then file:close() end
		if file or (message and not message:find("No such file", 1, true)) then table.insert(found, location) end
	end
	return found
end
local function exists(path)
	local file = io.open(path, "r")
	if file then file:close(); return true end
	return false
end
-- The path of a project marker beside `parent`, or nil. A marker with `*`
-- ("*.xcodeproj") matches a name in the folder.
local function markerPath(parent, marker)
	if marker:find("*", 1, true) then
		local pattern = "^" .. (marker:gsub("%p", "%%%0"):gsub("%%%*", ".*")) .. "$"
		for _, entry in ipairs(ns.readDirectory(parent, 0) or {}) do
			if entry.name:match(pattern) then return parent .. "/" .. entry.name end
		end
		return nil
	end
	if exists(parent .. "/" .. marker) then return parent .. "/" .. marker end
end
-- The repository a project lives in: the nearest folder at or above it,
-- up to the searched root, with a .git entry (a folder, or a file for
-- worktrees and submodules).
local function repositoryRoot(path, root)
	local current = path
	while current and #current >= #root do
		if exists(current .. "/.git") then return current end
		current = current:match("^(.*)/[^/]+$")
	end
	return nil
end
function System.discoverEntries(home, completion, projectRoots)
	local catalog = require("apps.diskmap.Catalog")
	local Projects = require("apps.diskmap.models.Projects")
	local locations = catalog.discoveryRules(home, projectRoots, System.hasFullDiskAccess())
	local discovered = {}
	local function runLocation(index)
		local location = locations[index]
		if not location then completion(discovered); return end
		local argv
		if location.rules then
			local roots = {}
			for _, root in ipairs(location.roots) do if exists(root) then table.insert(roots, root) end end
			if #roots == 0 then runLocation(index + 1); return end
			location.existing = roots
			argv = catalog.findArguments(roots, location.rules)
		else
			argv = {"/usr/bin/find", location.root, "-maxdepth", "1", "-type", "d", "-name", "*.app", "-print"}
		end
		System.command(argv, function(ok, output)
			-- find exits nonzero when one folder is unreadable; the paths it
			-- did print are still valid, and its messages never start with "/".
			if ok or location.rules then
				for _, path in ipairs(lines(output)) do
					local name = path:match("([^/]+)$") or path
					if location.rules and path:sub(1, 1) == "/" then
						local parent = path:match("^(.*)/[^/]+$") or ""
						for _, rule in ipairs(location.rules) do
							local marked
							if name == rule.dirName then
								for _, marker in ipairs(rule.markers) do
									marked = markerPath(parent, marker)
									if marked then break end
								end
							end
							if marked then
								local searched = ""
								for _, candidate in ipairs(location.existing) do
									if parent:sub(1, #candidate) == candidate and #candidate > #searched then searched = candidate end
								end
								if Projects.isToolFolder(parent, searched) then break end
								local proven = false
								for _, inner in ipairs(rule.inner) do if exists(path .. "/" .. inner) then proven = true; break end end
								local root = ""
								for _, candidate in ipairs(location.existing) do
									if parent:sub(1, #candidate) == candidate and #candidate > #root then root = candidate end
								end
								local project = Projects.displayName(parent, repositoryRoot(parent, root))
								local rebuildable = proven and rule.rebuildable == true
								table.insert(discovered, {id = hexId(path), name = rule.name .. " · " .. project, subtitle = rule.subtitle, path = path,
									policy = rebuildable and "Rebuildable" or "Review", action = rebuildable and "trash" or "finder",
									consequence = rebuildable and rule.consequence or nil, proof = proven and "marker and contents" or "marker",
									marker = marked, reviewThreshold = 500e6, icon = "shippingbox", color = "systemOrange",
									project = parent, projectName = project, artifact = rule.name})
								break
							end
						end
					elseif not location.rules and name:match("%.app$") then
						local installer = name:match("^Install macOS .+%.app$")
						table.insert(discovered, {id = hexId(path), name = name, subtitle = installer and "Full macOS installer app" or "Installed application",
							parentId = location.parentId, path = path, fileIcon = path, policy = "Review", action = "finder", reviewThreshold = installer and 5e9 or 1e9,
							consequence = installer and "Each installer is usually large. Keep it if you still need the installer; macOS Software Update can download it again later."
								or "Review this application in Finder or its own uninstaller. Diskmap will not remove installed applications.", icon = "app.fill", color = "systemBlue"})
					end
				end
			end
			runLocation(index + 1)
		end)
	end
	runLocation(1)
end
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
function System.snapshotCount(completion)
	System.command({"/usr/bin/tmutil", "listlocalsnapshots", "/"}, function(ok, output)
		local details = require("apps.diskmap.helpers.SystemDetails")
		local dates = ok and details.parseSnapshotDates(output) or nil
		completion(dates and #dates or nil, dates)
	end)
end
-- Software Update's record of its last check. It is world-readable and
-- offline, unlike `softwareupdate --list`, which contacts Apple.
function System.softwareUpdateStatus()
	return ns.readPropertyList("/Library/Preferences/com.apple.SoftwareUpdate.plist")
end
-- CoreSimulator's live state is authoritative for availability and whether
-- a device is running. A device folder alone cannot establish either.
function System.simulatorDevices(completion)
	System.command({"/usr/bin/xcrun", "simctl", "list", "devices", "-j"}, function(ok, output)
		local parsed, value = pcall(ns.json_parse, type(output) == "string" and output or "")
		if ok and parsed and type(value) == "table" and type(value.devices) == "table" then completion(value)
		else completion(nil, "Device state could not be checked. Retry or open Xcode to manage devices.") end
	end)
end
-- One device's current record, read just before a batch deletion touches it.
-- Completes with nil when the device is gone or CoreSimulator cannot say.
function System.simulatorState(udid, completion)
	System.simulatorDevices(function(listed)
		for _, devices in pairs(listed and listed.devices or {}) do
			for _, record in ipairs(devices) do
				if record.udid == udid then completion(record); return end
			end
		end
		completion(nil)
	end)
end
-- Installed simulator runtime images with their sizes.
-- Completes with nil when Xcode's tools are missing or the output is unreadable.
function System.simulatorRuntimes(completion)
	System.command({"/usr/bin/xcrun", "simctl", "runtime", "list", "-j"}, function(ok, output)
		if not ok or type(output) ~= "string" then completion(nil, "Runtimes could not be read. Retry or manage them in Xcode Components."); return end
		local parsed, value = pcall(ns.json_parse, output)
		completion(parsed and type(value) == "table" and value or nil,
			not (parsed and type(value) == "table") and "Runtime information could not be read. Retry or open Xcode Components." or nil)
	end)
end
-- Bundle identifier and version from each app's Info.plist, plus Spotlight's
-- last-used date, which Finder shows as "Last opened". One mdls call covers
-- every app; apps never opened have no date.
function System.applicationInfo(paths, completion)
	local info = {}
	-- An app that is open now is in use, whatever its last-used date says.
	local running = {}
	for _, id in ipairs(ns.runningApplications and ns.runningApplications() or {}) do running[id] = true end
	for _, path in ipairs(paths) do
		local plist = ns.readPropertyList(path .. "/Contents/Info.plist") or {}
		-- The name Finder and Launchpad show, which the bundle's file name
		-- ("logioptionsplus.app") need not be.
		local displayName = plist.CFBundleDisplayName or plist.CFBundleName
		info[path] = {bundleId = plist.CFBundleIdentifier, running = running[plist.CFBundleIdentifier] == true, version = plist.CFBundleShortVersionString or plist.CFBundleVersion,
			displayName = type(displayName) == "string" and displayName ~= "" and displayName or nil}
	end
	if #paths == 0 then completion(info); return end
	local argv = {"/usr/bin/mdls", "-raw", "-name", "kMDItemLastUsedDate"}
	for _, path in ipairs(paths) do table.insert(argv, path) end
	System.command(argv, function(ok, output)
		if ok then
			for path, lastUsed in pairs(require("apps.diskmap.models.Applications").parseLastUsed(output, paths)) do
				info[path].lastUsed = lastUsed
			end
		end
		completion(info)
	end)
end
-- Every application bundle Spotlight has indexed, anywhere on the Mac, so a
-- data folder is only called a leftover when no installed app claims it.
-- Completes with nil when Spotlight is unavailable.
function System.installedBundleIds(completion)
	System.command({"/usr/bin/mdfind", "kMDItemContentType == 'com.apple.application-bundle'"}, function(ok, output)
		if not ok then completion(nil); return end
		local paths = lines(output)
		if #paths == 0 then completion(nil); return end
		local argv = {"/usr/bin/mdls", "-raw", "-name", "kMDItemCFBundleIdentifier"}
		for _, path in ipairs(paths) do table.insert(argv, path) end
		System.command(argv, function(listed, values)
			if not listed then completion(nil); return end
			local ids = {}
			for value in ((values or "") .. "\0"):gmatch("([^%z]*)%z") do
				if value ~= "" and value ~= "(null)" then table.insert(ids, value) end
			end
			completion(ids)
		end)
	end)
end
-- `diskutil apfs list -plist` and the startup volume's container: each
-- APFS volume's own used space, mounted or not. Measuring Preboot, Recovery
-- and swap by volume is exact where adding up their files is not.
function System.apfsVolumes(completion)
	System.command({"/usr/sbin/diskutil", "info", "-plist", "/"}, function(ok, infoText)
		local info = ok and ns.parsePropertyList(infoText) or nil
		System.command({"/usr/sbin/diskutil", "apfs", "list", "-plist"}, function(listed, listText)
			completion(listed and ns.parsePropertyList(listText) or nil, info and info.APFSContainerReference)
		end)
	end)
end
-- Startup disk facts from diskutil and other mounted volumes. Reading them
-- changes nothing; repairs stay in Disk Utility.
function System.volumes(completion)
	System.command({"/usr/sbin/diskutil", "info", "-plist", "/"}, function(ok, infoText)
		local info = ok and ns.parsePropertyList(infoText) or nil
		System.command({"/usr/sbin/diskutil", "apfs", "list", "-plist"}, function(listed, listText)
			local external = {}
			for _, entry in ipairs(ns.readDirectory("/Volumes", 0) or {}) do
				local space = entry.directory and ns.diskSpace(entry.path)
				local root = ns.diskSpace("/")
				-- The startup volume also appears under /Volumes; skip it.
				if space and not (root and space.totalKb == root.totalKb and space.freeKb == root.freeKb) then
					table.insert(external, {name = entry.name, path = entry.path, totalBytes = space.totalKb * 1024, freeBytes = space.freeKb * 1024})
				end
			end
			completion({info = info, apfs = listed and ns.parsePropertyList(listText) or nil, external = external})
		end)
	end)
end
-- A folder's immediate children, such as another disk's top level or a
-- watched folder, measured like the startup disk: metadata only, staying on
-- that volume.
function System.analyzeFolder(path, completion)
	local ok, job = pcall(Scanner.start, {path}, {}, {breakdown = true})
	if not ok then completion(nil, tostring(job)); return end
	System.await(job, function(result)
		local breakdown = result.breakdowns and result.breakdowns[1]
		completion(breakdown, result.failure ~= "" and result.failure or nil, result.errors)
	end)
end
-- Everything under `path` as one tree of its largest folders and files
-- (see `treeDepth` in src/plugins/storage/README.md): what the Folder page
-- maps. `progress(items)` reports items met so far while it runs;
-- `completion(folder, failure, stats)` receives the root node and
-- `{errors, visited}`. Returns the job for `cancelFolderScan`.
-- The startup disk's files live on its Data volume, mounted at
-- /System/Volumes/Data and joined to "/" by firmlinks; "/" itself is the
-- sealed system volume. The scan stays on one volume, so "/" is measured
-- through the Data volume and reported under the paths people know.
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
-- Moves a file or folder into `folder`; `completion(ok, message, destination)`.
function System.moveItem(path, folder, completion) ns.moveItem(path, folder, completion) end
function System.quickLook(paths, index) ns.quickLook(paths, index) end
function System.onOpenFiles(handler) ns.onOpenFiles(handler) end
function System.openDiskUtility()
	os.execute("/usr/bin/open -a " .. System.quote("Disk Utility"))
end
function System.copy(text) ns.copyToClipboard(text) end
function System.confirmTrashPath(title, path, message)
	return ns.Alert {title = title, message = path .. "\n\n" .. message, buttons = {"Cancel", "Move to Trash"}} == 2
end
local support = System.supportPath
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
function System.exists(path)
	local file = io.open(expand(path), "r")
	if file then file:close(); return true end
	return false
end
function System.volumeCapacity(path) return ns.volumeCapacity(path or "/") end
function System.pickFolder(title) return ns.pickFolder(title) end
-- Inside the App Sandbox macOS shows Diskmap only its container and what the
-- person chooses in an open panel, whatever Full Disk Access says: the
-- sandbox is checked first. So the App Store build asks once for the startup
-- disk, as DaisyDisk does, and keeps it as a security-scoped bookmark.
-- Full Disk Access then opens the folders macOS protects inside it.
function System.sandboxed() return os.getenv("APP_SANDBOX_CONTAINER_ID") ~= nil end
local diskAccess
function System.hasDiskAccess()
	if not System.sandboxed() then return true end
	if diskAccess == nil then
		local bookmark = readFile(support("disk-access"))
		diskAccess = bookmark ~= nil and bookmark ~= "" and ns.resolveBookmark(bookmark) == "/"
	end
	return diskAccess
end
function System.requestDiskAccess()
	local path = ns.pickFolder("Allow Diskmap to Measure Your Disk", {directory = "/",
		message = "Click Allow to let Diskmap measure your startup disk. It reads only names, sizes and dates.",
		prompt = "Allow"})
	if not path then return false end
	if path ~= "/" then
		System.showError("Choose your startup disk", "Diskmap measures the whole disk, so it needs the disk itself, not " .. path .. ". Select Macintosh HD in the sidebar and click Allow.")
		return false
	end
	local bookmark = ns.bookmark(path)
	if bookmark then writeFile(support("disk-access"), bookmark) end
	diskAccess = true
	return true
end
function System.pickFile(title) return ns._pickFile(title) end
function System.pickSaveFile(title, name) return ns._saveFile(title, name) end
-- Folder lists the person chose ("projects", "duplicates"): one
-- "path<TAB>bookmark" line each. The security-scoped bookmark follows a moved
-- or renamed folder and keeps access should Diskmap run sandboxed.
function System.loadFolders(name)
	local roots = {}
	for line in (readFile(support(name .. "-folders")) or ""):gmatch("[^\n]+") do
		local path, bookmark = line:match("^([^\t]*)\t?(.*)$")
		local resolved = bookmark ~= "" and ns.resolveBookmark(bookmark)
		table.insert(roots, resolved or path)
	end
	return roots
end
function System.saveFolders(name, roots)
	local lines = {}
	for _, path in ipairs(roots) do table.insert(lines, path .. "\t" .. (ns.bookmark(path) or "")) end
	return writeFile(support(name .. "-folders"), table.concat(lines, "\n"))
end
-- Duplicate files in chosen folders: reads their contents, so it runs only
-- when asked and only there. Returns a job whose `cancel()` stops it.
function System.findDuplicates(roots, completion, progress)
	local job = Scanner.startDuplicates(roots, {minimumBytes = 1e6})
	ns.async(function()
		while not job.cancelled do
			local done, result = Scanner.pollDuplicates(job)
			if done then completion(result); return end
			if result and progress then progress(result) end
			ns.sleep(0.25)
		end
	end)
	return {cancel = function() Scanner.cancelDuplicates(job) end}
end
-- Opt-in features stored as one small file each: "enabled" or absent.
function System.loadFlag(name) return readFile(support("flag-" .. name)) == "enabled" end
function System.saveFlag(name, enabled) return writeFile(support("flag-" .. name), enabled and "enabled" or "disabled") end
-- Notifications need the Diskmap app bundle; the development runtime has none.
function System.notificationsAvailable() return ns.notifications.available() end
function System.requestNotifications(callback) ns.notifications.requestAuthorization(callback) end
function System.notify(options, onResponse) return ns.notifications.post(options, onResponse) end
function System.removeNotification(id) ns.notifications.remove(id) end
-- Watches folders while Diskmap runs; the handle's cancel() stops it.
function System.watch(paths, callback)
	local expanded = {}
	for _, path in ipairs(paths) do table.insert(expanded, expand(path)) end
	return ns.watch(expanded, callback)
end
function System.loadHistorySetting() return readFile(support("history-enabled")) == "enabled" end
function System.saveHistorySetting(enabled) return writeFile(support("history-enabled"), enabled and "enabled" or "disabled") end
function System.loadHistory() return readFile(support("history")) or "" end
-- Per-location totals of the saved snapshot, keyed by its creation time.
function System.loadSnapshotSummary() return readFile(support("snapshot-summary")) or "" end
function System.saveSnapshotSummary(text) return writeFile(support("snapshot-summary"), text) end
function System.saveHistory(text) return writeFile(support("history"), text) end
-- Actions are appended to a plain text log that Console can open too.
local LOG = (os.getenv("HOME") or "") .. "/Library/Logs/Diskmap/operations.log"
function System.logOperation(line) return writeFile(LOG, line .. "\n", true) end
function System.operationLog()
	local lines = {}
	for line in (readFile(LOG) or ""):gmatch("[^\n]+") do table.insert(lines, line) end
	return lines
end
-- /usr/bin/git is a shim that offers to install the developer tools when
-- they are missing; ask xcode-select first so no installer prompt appears.
local developerTools
local function withDeveloperTools(completion)
	if developerTools ~= nil then completion(developerTools); return end
	System.command({"/usr/bin/xcode-select", "-p"}, function(ok)
		developerTools = ok == true
		completion(developerTools)
	end)
end
-- Git state and last modification of a project folder, never touching files.
-- "Last worked": the newest of the git index, HEAD and the project's own
-- files, skipping generated folders, which a build touches without anyone
-- working on the project. Falls back to the folder's own date.
local function lastWorkedArguments(path)
	local catalog = require("apps.diskmap.Catalog")
	local argv = {"/usr/bin/find", path, "-maxdepth", "8", "(", "-name", ".git"}
	local seen = {}
	for _, rule in ipairs(catalog.buildRules()) do
		if not seen[rule.dirName] then
			seen[rule.dirName] = true
			for _, value in ipairs({"-o", "-name", rule.dirName}) do table.insert(argv, value) end
		end
	end
	for _, value in ipairs({")", "-prune", "-o", "-type", "f", "-exec", "/usr/bin/stat", "-f", "%m", "{}", "+"}) do table.insert(argv, value) end
	return argv
end
function System.projectInfo(path, completion)
	local Projects = require("apps.diskmap.models.Projects")
	local function finish(modified)
		withDeveloperTools(function(available)
			if not available then completion({modified = modified, loaded = true}); return end
			System.command({"/usr/bin/git", "-C", path, "status", "--porcelain=v1", "--branch"}, function(gitOk, gitOutput)
				completion({modified = modified, git = gitOk and Projects.parseGit(gitOutput) or nil, loaded = true})
			end)
		end)
	end
	-- stat and find exit nonzero when a git file is absent; what they
	-- printed still counts.
	System.command(lastWorkedArguments(path), function(_, files)
		System.command({"/usr/bin/stat", "-f", "%m", path .. "/.git/index", path .. "/.git/HEAD"}, function(_, gitTimes)
			local worked = Projects.lastWorked((gitTimes or "") .. "\n" .. (files or ""))
			if worked then finish(worked); return end
			System.command({"/usr/bin/stat", "-f", "%m", path}, function(ok, output)
				finish(ok and tonumber((output or ""):match("%d+")) or nil)
			end)
		end)
	end)
end
-- Disk images and installer packages in the places downloads end up.
function System.findInstallers(home, completion)
	local argv = {"/usr/bin/find", home .. "/Downloads", home .. "/Desktop", home .. "/Documents", "-maxdepth", "4", "-type", "f",
		"(", "-iname", "*.dmg", "-o", "-iname", "*.pkg", "-o", "-iname", "*.xip", "-o", "-iname", "*.iso", ")", "-size", "+10M", "-print"}
	System.command(argv, function(_, output)
		local paths = lines(output or "")
		if #paths == 0 then completion({}); return end
		System.measure(paths, function(sizes)
			local files = {}
			for index, path in ipairs(paths) do table.insert(files, {path = path, bytes = sizes[index]}) end
			completion(files)
		end)
	end)
end
-- Leftover Git worktrees: every repository under the project folders and the
-- tools' own worktree roots, with each worktree's evidence. Completes with
-- (entries, facts-by-path).
function System.worktreeScan(roots, completion, progress)
	local Service = require("apps.diskmap.services.Worktrees")
	local home = System.home
	local searched = {}
	for _, root in ipairs(roots or {}) do table.insert(searched, root) end
	for _, root in ipairs({home .. "/.codex/worktrees", home .. "/.claude"}) do table.insert(searched, root) end
	local existing = {}
	for _, root in ipairs(searched) do if exists(root) then table.insert(existing, root) end end
	if #existing == 0 then completion({}, {}); return end
	Service.repositories(System.command, existing, function(repos)
		Service.list(System.command, repos, function(entries)
			if progress then progress(0, #entries) end
			Service.allFacts(System.command, System.measure, entries, function(facts) completion(entries, facts) end, progress)
		end)
	end)
end
-- One worktree's current record and evidence, read just before its removal.
function System.worktreeState(row, completion)
	local Service = require("apps.diskmap.services.Worktrees")
	Service.list(System.command, {{path = row.repository, commonDir = row.commonDir}}, function(entries)
		for _, entry in ipairs(entries) do
			if entry.path == row.path then
				Service.facts(System.command, System.measure, entry, function(facts) completion(entry, facts) end)
				return
			end
		end
		completion(nil, nil)
	end)
end
System.decode = ns.json_parse
function System.confirmAction(title, message)
	return ns.Alert {title = title, message = message, buttons = {"Cancel", title}} == 2
end
return System
