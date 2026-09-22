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
	if #value > 0 then for _, v in ipairs(value) do out[#out + 1] = json(v) end; return "[" .. table.concat(out, ",") .. "]" end
	for k, v in pairs(value) do out[#out + 1] = json(k) .. ":" .. json(v) end
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
function System.start(paths, exclusions)
	local pipe = assert(io.popen("/usr/bin/mktemp -d /tmp/diskmap.XXXXXXXX"))
	local directory = pipe:read("*l")
	pipe:close()
	assert(directory and directory:match("^/tmp/diskmap%.%w+$"), "Cannot create private scan directory")
	local output = directory .. "/result.json"
	local args = {}
	local plan = directory .. "/plan.json"
	local file = assert(io.open(plan, "w")); file:write(json({roots = paths, exclusions = exclusions or {}})); file:close()
	args[1] = System.quote(plan)
	local command = "/usr/bin/nice -n 10 /usr/bin/perl " .. System.quote("apps/diskmap/services/scan.pl") .. " " .. System.quote(output) .. ' "$PPID" ' .. table.concat(args, " ")
	local launcher = assert(io.popen(command .. " </dev/null >" .. System.quote(directory .. "/error") .. " 2>&1 & echo $!"))
	local pid = tonumber(launcher:read("*l"))
	launcher:close()
	return {directory = directory, output = output, pid = pid, started = os.time()}
end
function System.cancel(job)
	if not job then return end
	if job.pid then os.execute("/bin/kill " .. tostring(job.pid) .. " 2>/dev/null") end
	for _, file in ipairs({"result.json", "result.json.tmp", "error", "plan.json", "progress.json", "progress.json.tmp"}) do os.remove(job.directory .. "/" .. file) end
	os.remove(job.directory)
end
function System.poll(job)
	local file = io.open(job.output, "rb")
	if file then
		local body = file:read("*a"); file:close()
		local ok, result = pcall(ns.json_parse, body)
		job.pid = nil
		System.cancel(job)
		return true, ok and result or {failure = "Could not read scan results."}
	end
	local errorFile = io.open(job.directory .. "/error", "r")
	if errorFile then
		local problem = errorFile:read("*a"); errorFile:close()
		if #problem > 0 then System.cancel(job); return true, {failure = "Scanner failed: " .. problem:sub(1, 400)} end
	end
	if os.time() - job.started > 610 then
		System.cancel(job)
		return true, {failure = "Scan timed out. Try a smaller folder."}
	end
	local progressFile = io.open(job.directory .. "/progress.json", "r")
	if progressFile then
		local body = progressFile:read("*a"); progressFile:close()
		local ok, progress = pcall(ns.json_parse, body)
		if ok then return false, progress end
	end
	return false
end
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
	local target = section == "privacy" and "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" or "x-apple.systempreferences:com.apple.settings.Storage"
	os.execute("/usr/bin/open " .. System.quote(target))
end
function System.openOwner(owner)
	os.execute("/usr/bin/open -a " .. System.quote(owner == "xcode" and "Xcode" or "Docker"))
end
function System.confirmTrash(row)
	return ns.Alert {title = "Move " .. row.name .. " to Trash?", message = row.path .. "\n\n" .. row.consequence, buttons = {"Cancel", "Move to Trash"}} == 2
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
return System
