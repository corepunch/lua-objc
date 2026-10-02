local Format = require("apps.diskmap.helpers.Format")
local Xcode = {}

-- Where Xcode keeps per-device symbols, per-project build data and shipped
-- builds. Each folder here is one reviewable unit; Diskmap never reaches
-- inside an archive or a DerivedData project folder.
Xcode.deviceSupport = {
	{platform = "iOS", path = "~/Library/Developer/Xcode/iOS DeviceSupport"},
	{platform = "watchOS", path = "~/Library/Developer/Xcode/watchOS DeviceSupport"},
	{platform = "tvOS", path = "~/Library/Developer/Xcode/tvOS DeviceSupport"},
	{platform = "visionOS", path = "~/Library/Developer/Xcode/visionOS DeviceSupport"},
}
Xcode.derivedData = "~/Library/Developer/Xcode/DerivedData"
Xcode.archives = "~/Library/Developer/Xcode/Archives"

-- Device Support folders are named "17.2 (21C62)" or, since Xcode 15,
-- "iPhone15,2 17.2 (21C62)". Returns version parts for sorting.
function Xcode.parseSupport(name)
	local model, version, build = name:match("^(%S+%d+,%d+)%s+([%d%.]+)%s*%(([^)]+)%)")
	if not version then version, build = name:match("^([%d%.]+)%s*%(([^)]+)%)") end
	if not version then version = name:match("^([%d%.]+)") end
	local parts = {}
	for number in (version or ""):gmatch("%d+") do table.insert(parts, tonumber(number)) end
	return {model = model, version = version, build = build, parts = parts}
end

local function newer(a, b)
	for index = 1, math.max(#a, #b) do
		local x, y = a[index] or 0, b[index] or 0
		if x ~= y then return x > y end
	end
	return false
end

-- Rows for Device Support entries ({platform, name, path, bytes}), newest
-- first per platform. The newest version of each platform is kept: it is
-- the one a connected device most likely needs.
function Xcode.supportRows(entries)
	local rows = {}
	for _, entry in ipairs(entries or {}) do
		local parsed = Xcode.parseSupport(entry.name)
		table.insert(rows, {id = entry.path, path = entry.path, platform = entry.platform, parts = parsed.parts,
			name = entry.platform .. " " .. (parsed.version or entry.name),
			subtitle = table.concat({parsed.build and ("Build " .. parsed.build) or nil, parsed.model}, " · "),
			bytes = entry.bytes, size = Format.size(entry.bytes)})
	end
	table.sort(rows, function(a, b)
		if a.platform ~= b.platform then return a.platform < b.platform end
		if newer(a.parts, b.parts) ~= newer(b.parts, a.parts) then return newer(a.parts, b.parts) end
		return a.path < b.path
	end)
	local seen = {}
	for _, row in ipairs(rows) do
		row.keep = not seen[row.platform]
		seen[row.platform] = true
		row.status = row.keep and "Newest · keep" or "Older"
		row.parts = nil
	end
	return rows
end

-- Folders Xcode keeps in DerivedData for every project at once. They are
-- caches, not projects, so they are named for what they hold and never
-- counted as a project whose workspace is unknown.
Xcode.sharedCaches = {
	["ModuleCache.noindex"] = "Module cache",
	["SymbolCache.noindex"] = "Symbol cache",
	["SDKStatCaches.noindex"] = "SDK file cache",
	["CompilationCache.noindex"] = "Compilation cache",
	["SDKExplicitPrecompiledModules"] = "Precompiled SDK modules",
}
function Xcode.sharedCache(name)
	if Xcode.sharedCaches[name] then return Xcode.sharedCaches[name] end
	if type(name) == "string" and name:match("%.noindex$") then return (name:gsub("%.noindex$", "")) end
	return nil
end

-- DerivedData folders are "<Project>-<hash>". Their info.plist names the
-- workspace; a workspace that no longer exists marks build data nothing can
-- reuse. Shared caches follow the projects.
function Xcode.derivedRows(entries)
	local rows = {}
	for _, entry in ipairs(entries or {}) do
		local shared = Xcode.sharedCache(entry.name)
		if shared then
			table.insert(rows, {id = entry.path, path = entry.path, name = shared, bytes = entry.bytes, size = Format.size(entry.bytes),
				subtitle = "Shared by every project · Xcode rebuilds it", missing = false, shared = true, status = "Shared"})
			goto continue
		end
		local workspace = type(entry.workspace) == "string" and entry.workspace or nil
		local name = workspace and workspace:match("([^/]+)%.xc[a-z]+$")
			or entry.name:match("^(.-)%-%l+$") or entry.name
		local missing = workspace ~= nil and entry.exists == false
		table.insert(rows, {id = entry.path, path = entry.path, name = name, bytes = entry.bytes, size = Format.size(entry.bytes),
			subtitle = workspace or "Workspace not recorded", missing = missing,
			status = missing and "Missing" or workspace and "Present" or "Unknown"})
		::continue::
	end
	table.sort(rows, function(a, b)
		if a.missing ~= b.missing then return a.missing end
		if (a.shared == true) ~= (b.shared == true) then return b.shared == true end
		if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end
		return a.path < b.path
	end)
	return rows
end

-- Archives ({path, name, plist, bytes}): app, version and creation date from
-- the archive's Info.plist, oldest first so review starts with the least
-- likely to be needed. Archives are never pre-selected.
function Xcode.archiveRows(entries)
	local rows = {}
	for _, entry in ipairs(entries or {}) do
		local plist = type(entry.plist) == "table" and entry.plist or {}
		local properties = type(plist.ApplicationProperties) == "table" and plist.ApplicationProperties or {}
		local version = properties.CFBundleShortVersionString
		local build = properties.CFBundleVersion
		local created = type(plist.CreationDate) == "string" and plist.CreationDate:sub(1, 10)
			or type(entry.date) == "string" and entry.date or ""
		table.insert(rows, {id = entry.path, path = entry.path,
			name = type(plist.Name) == "string" and plist.Name or entry.name:gsub("%.xcarchive$", ""),
			subtitle = version and ("Version " .. version .. (build and (" (" .. build .. ")") or "")) or "Version not recorded",
			date = created, status = created ~= "" and ("Created " .. created) or "Date unknown",
			bytes = entry.bytes, size = Format.size(entry.bytes)})
	end
	table.sort(rows, function(a, b)
		if a.date ~= b.date then return a.date < b.date end
		return a.path < b.path
	end)
	return rows
end

function Xcode.total(rows, filter)
	local bytes = 0
	for _, row in ipairs(rows or {}) do
		if not filter or filter(row) then bytes = bytes + (row.bytes or 0) end
	end
	return bytes
end

return Xcode
