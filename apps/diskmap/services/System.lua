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
function System.writeCache(path, data)
	local f, err = io.open(path .. ".tmp", "w"); if not f then return false, err end
	f:write(json(data)); f:close(); return os.rename(path .. ".tmp", path)
end
function System.readCache(path)
	local f, err = io.open(path, "r"); if not f then return nil, err end
	local body = f:read("*a"); f:close()
	local ok, data = pcall(ns.json_parse, body)
	if not ok or type(data) ~= "table" or data.version ~= require("apps.diskmap.Catalog").version or type(data.measurements) ~= "table" then return nil, "Invalid Diskmap cache" end
	local statuses = {complete = true, partial = true, denied = true, stale = true, unsupported = true, skipped = true}
	for id, m in pairs(data.measurements) do
		if type(id) ~= "string" or type(m) ~= "table" or (m.bytes ~= nil and (type(m.bytes) ~= "number" or m.bytes < 0 or m.bytes ~= m.bytes or m.bytes == math.huge)) or not statuses[m.status] then return nil, "Invalid measurements" end
	end
	if data.disk and (type(data.disk) ~= "table" or type(data.disk.totalKb) ~= "number" or type(data.disk.freeKb) ~= "number" or data.disk.totalKb <= 0 or data.disk.freeKb < 0 or data.disk.freeKb > data.disk.totalKb) then return nil, "Invalid cached capacity" end
	return data
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
	return System.writeCache(directory .. "/kept.json", kept)
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
function System.defaultCachePath()
	local directory = (os.getenv("HOME") or "") .. "/Library/Application Support/Diskmap"
	if not os.execute("/bin/mkdir -p " .. System.quote(directory)) then return nil end
	return directory .. "/last-scan.json"
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
