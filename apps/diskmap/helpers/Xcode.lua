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

-- Rows for Device Support entries ({platform, name, path, bytes, used}),
-- newest first per platform. The newest version of each platform is kept:
-- it is the one a connected device most likely needs; older ones Xcode
-- copies again from the device the next time it runs that version.
function Xcode.supportRows(entries)
	local rows = {}
	for _, entry in ipairs(entries or {}) do
		local parsed = Xcode.parseSupport(entry.name)
		table.insert(rows, {id = entry.path, path = entry.path, platform = entry.platform, parts = parsed.parts,
			name = entry.platform .. " " .. (parsed.version or entry.name), owner = "Xcode",
			what = "Debug symbols Xcode copied from a device running " .. (parsed.version or entry.name) .. (parsed.model and (" (" .. parsed.model .. ")") or "") .. ". Xcode copies them again the next time it debugs a device on this version.",
			bytes = entry.bytes, used = entry.used, state = entry.state or "measured"})
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
		row.verdict = row.keep and "keep" or "safe"
		row.reason = row.keep and ("The newest " .. row.platform .. " version on this Mac: the one a connected device most likely needs.")
			or ("An older " .. row.platform .. " version. Xcode copies the symbols again when it next debugs a device on it.")
		row.action = row.keep and "none" or "trash"
		row.parts = nil
	end
	return rows
end

-- Folders Xcode keeps in DerivedData for every project at once. They are
-- caches, not projects, so they are named for what they hold.
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
		local base = {id = entry.path, path = entry.path, bytes = entry.bytes, used = entry.used, state = entry.state or "measured", owner = "Xcode", action = "trash"}
		if shared then
			base.name, base.shared, base.verdict = shared, true, "safe"
			base.what = "A cache Xcode shares between every project. Xcode rebuilds it."
			base.reason = "Shared by every project and rebuilt by Xcode as it builds."
		else
			local workspace = type(entry.workspace) == "string" and entry.workspace or nil
			base.name = workspace and workspace:match("([^/]+)%.xc[a-z]+$") or entry.name:match("^(.-)%-%l+$") or entry.name
			base.missing = workspace ~= nil and entry.exists == false
			base.workspace = workspace
			base.what = "Build products and the code index of " .. base.name .. ". The next build and indexing of the project take longer without them."
			if base.missing then
				base.verdict, base.reason = "safe", "Its project, " .. workspace .. ", no longer exists, so nothing can reuse this build data."
			elseif workspace then
				base.verdict, base.reason = "review", "Its project is still at " .. workspace .. ". Xcode rebuilds the data on the next build, which takes longer."
			else
				base.verdict, base.reason = "review", "Xcode did not record which project this belongs to."
			end
		end
		table.insert(rows, base)
	end
	table.sort(rows, function(a, b)
		if (a.missing == true) ~= (b.missing == true) then return a.missing == true end
		if (a.shared == true) ~= (b.shared == true) then return b.shared == true end
		if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end
		return a.path < b.path
	end)
	return rows
end

-- Archives ({path, name, plist, bytes, used}): app, version and creation
-- date from the archive's Info.plist, oldest first so review starts with the
-- least likely to be needed. Archives are never called safe: without one,
-- crash reports for that version cannot be symbolicated.
function Xcode.archiveRows(entries)
	local rows = {}
	for _, entry in ipairs(entries or {}) do
		local plist = type(entry.plist) == "table" and entry.plist or {}
		local properties = type(plist.ApplicationProperties) == "table" and plist.ApplicationProperties or {}
		local version = properties.CFBundleShortVersionString
		local build = properties.CFBundleVersion
		local created = type(plist.CreationDate) == "string" and plist.CreationDate:sub(1, 10)
			or type(entry.date) == "string" and entry.date or ""
		local name = type(plist.Name) == "string" and plist.Name or entry.name:gsub("%.xcarchive$", "")
		table.insert(rows, {id = entry.path, path = entry.path, name = name, owner = "Xcode",
			detail = version and ("Version " .. version .. (build and (" (" .. build .. ")") or "")) or "Version not recorded",
			date = created, bytes = entry.bytes, used = entry.used, state = entry.state or "measured", verdict = "review", action = "trash",
			what = "A shipped build of " .. name .. " with its debug symbols" .. (created ~= "" and (", archived " .. created) or "") .. ". Without it, crash reports for this version cannot be symbolicated.",
			reason = "Keep archives of versions people still run; Diskmap cannot tell which those are."})
	end
	table.sort(rows, function(a, b)
		if a.date ~= b.date then return a.date < b.date end
		return a.path < b.path
	end)
	return rows
end

return Xcode
