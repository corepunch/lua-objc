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
