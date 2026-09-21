local ns = require("AppKit")
local System = {}
function System.quote(value)
	assert(type(value) == "string" and not value:find("\0", 1, true), "Invalid path")
	return "'" .. value:gsub("'", "'\\''") .. "'"
end
function System.start(paths, mode)
	local pipe = assert(io.popen("/usr/bin/mktemp -d /tmp/diskmap.XXXXXXXX"))
	local directory = pipe:read("*l")
	pipe:close()
	assert(directory and directory:match("^/tmp/diskmap%.%w+$"), "Cannot create private scan directory")
	local output = directory .. "/result.json"
	local args = {}
	for _, path in ipairs(paths) do args[#args + 1] = System.quote(path) end
	local command = "/usr/bin/nice -n 10 /usr/bin/perl " .. System.quote("apps/diskmap/services/scan.pl") .. " " .. System.quote(output) .. ' "$PPID" ' .. System.quote(mode or "tree") .. " " .. table.concat(args, " ")
	local launcher = assert(io.popen(command .. " </dev/null >" .. System.quote(directory .. "/error") .. " 2>&1 & echo $!"))
	local pid = tonumber(launcher:read("*l"))
	launcher:close()
	return {directory = directory, output = output, pid = pid, started = os.time()}
end
function System.cancel(job)
	if not job then return end
	if job.pid then os.execute("/bin/kill " .. tostring(job.pid) .. " 2>/dev/null") end
	for _, file in ipairs({"result.json", "result.json.tmp", "error"}) do os.remove(job.directory .. "/" .. file) end
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
	return false
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
System.pickFolder = function() return ns._pickFolder("Choose a folder to measure") end
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
