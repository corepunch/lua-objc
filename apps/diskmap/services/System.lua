local ns = require("AppKit")
local System = {}
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
function System.loadKeep()
	local f = io.open((os.getenv("HOME") or "") .. "/Library/Application Support/Diskmap/kept.json", "r")
	if not f then return {} end
	local body = f:read("*a"); f:close()
	local ok, value = pcall(ns.json_parse, body)
	return ok and type(value) == "table" and value or {}
end
function System.saveKeep(kept)
	local directory = (os.getenv("HOME") or "") .. "/Library/Application Support/Diskmap"
	if not os.execute("/bin/mkdir -p " .. System.quote(directory)) then return false end
	local path = directory .. "/kept.json"
	local file = io.open(path .. ".tmp", "w"); if not file then return false end
	file:write(json(kept)); file:close()
	return os.rename(path .. ".tmp", path)
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
	local paths = {
		"/", "/Users", "/Applications", "/Library", "/private", "/opt", "/usr/local",
		"/System/Volumes/Data", "/System/Volumes/Preboot", "/System/Volumes/Recovery",
		"/System/Volumes/Update", "/System/Volumes/xarts", "/System/Volumes/Hardware", "/System/Volumes/iSCPreboot",
	}
	local exclusions = {"/Volumes", "/dev", "/System/Volumes"}
	local ok, job = pcall(Scanner.startExport, paths, exclusions, outputPath, {
		capacityBytes = disk.totalKb * 1024,
		availableBytes = disk.freeKb * 1024,
		logicalRoots = { ["/System/Volumes/Data"] = "/" },
	})
	if not ok then completion({failure = tostring(job)}); return end
	System.await(job, completion)
end
function System.loadSettings()
	local file = io.open((os.getenv("HOME") or "") .. "/Library/Application Support/Diskmap/background", "r")
	if not file then return true end
	local value = file:read("*l"); file:close()
	return value ~= "paused"
end
function System.saveSettings(enabled)
	local directory = (os.getenv("HOME") or "") .. "/Library/Application Support/Diskmap"
	local ok = os.execute("/bin/mkdir -p " .. System.quote(directory))
	if not ok then return false end
	local file = io.open(directory .. "/background", "w")
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
	}
	local target = "x-apple.systempreferences:" .. (targets[section] or "com.apple.settings.Storage")
	os.execute("/usr/bin/open " .. System.quote(target))
end
function System.openOwner(owner)
	os.execute("/usr/bin/open -a " .. System.quote(owner == "xcode" and "Xcode" or "Docker"))
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
	}
	local argv = commands[commandId]
	if not argv then completion(false, "Unsupported package-manager cache operation."); return end
	System.command(argv, completion)
end
function System.emptyTrash()
	return os.execute("/usr/bin/osascript -e 'tell application \"Finder\" to empty trash'")
end
function System.showError(title, message) ns.Alert {title = title, message = message} end
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
		local root = model.resources:find(id .. "-other")
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
function System.discoverEntries(home, completion)
	local catalog = require("apps.diskmap.Catalog")
	local locations = catalog.discoveryRules(home)
	local discovered = {}
	local function runLocation(index)
		local location = locations[index]
		if not location then completion(discovered); return end
		local argv
		if location.rules then
			argv = {"/usr/bin/find", location.root, "-type", "d", "(", "-name", location.rules[1].dirName}
			for ruleIndex = 2, #location.rules do
				table.insert(argv, "-o"); table.insert(argv, "-name"); table.insert(argv, location.rules[ruleIndex].dirName)
			end
			table.insert(argv, ")"); table.insert(argv, "-prune"); table.insert(argv, "-print")
		else
			argv = {"/usr/bin/find", location.root, "-maxdepth", "1", "-type", "d", "-name", "*.app", "-print"}
		end
		System.command(argv, function(ok, output)
			if ok then
				for _, path in ipairs(lines(output)) do
					local name = path:match("([^/]+)$") or path
					if location.rules then
						local parent = path:match("^(.*)/[^/]+$") or ""
						for _, rule in ipairs(location.rules) do
							local marker = name == rule.dirName and io.open(parent .. "/" .. rule.markerFile, "r")
							if marker then
								marker:close()
								table.insert(discovered, {id = hexId(path), name = rule.name .. " · " .. (parent:match("([^/]+)$") or parent), subtitle = rule.subtitle, path = path,
									policy = "Review", action = "finder", reviewThreshold = 500e6, icon = "shippingbox", color = "systemOrange"})
								break
							end
						end
					elseif name:match("%.app$") then
						local installer = name:match("^Install macOS .+%.app$")
						table.insert(discovered, {id = hexId(path), name = name, subtitle = installer and "Full macOS installer app" or "Installed application",
							parentId = location.parentId, path = path, policy = "Review", action = "finder", reviewThreshold = installer and 5e9 or 1e9,
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
		local details = require("apps.diskmap.models.SystemDetails")
		local dates = ok and details.parseSnapshotDates(output) or nil
		completion(dates and #dates or nil, dates)
	end)
end
System.decode = ns.json_parse
function System.confirmAction(title, message)
	return ns.Alert {title = title, message = message, buttons = {"Cancel", title}} == 2
end
return System
