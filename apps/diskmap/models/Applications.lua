local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Applications = {}

-- An app's data lives outside its bundle, in folders named by its bundle
-- identifier (or, for Application Support, sometimes its name). These are
-- the catalog locations whose immediate children the scan already measured.
Applications.dataSources = {
	{id = "app-containers", label = "Container", byId = true},
	{id = "group-containers", label = "Group container", contains = true},
	{id = "support", label = "Application Support", byId = true, byName = true},
	{id = "user-caches", label = "Caches", byId = true},
}
Applications.filters = {"All", "Unused for 6 months", "Most data"}
Applications.unusedDays = 180
-- Folders smaller than this are not worth listing as possible leftovers.
Applications.leftoverMinimum = 50e6

local function reverseDNS(name)
	return name:match("^[%w%-]+%.[%w%-]+%.[%w%.%-]+$") ~= nil
end
local function apple(name)
	return name:lower():match("^com%.apple%.") ~= nil or name:lower():match("^group%.com%.apple%.") ~= nil
end

-- Installed application bundles: discovered `.app` resources, plus catalog
-- apps such as Xcode when they exist. A bundle the scan found missing is not
-- installed.
function Applications.bundles(model)
	local rows = {}
	for _, row in ipairs(model.resources:leaves()) do
		local m = model.measurements[row.id]
		local missing = m and m.status == "complete" and (m.bytes or 0) == 0
		if row.path and row.path:match("%.app$") and not missing then table.insert(rows, row) end
	end
	return rows
end

-- The data folders that belong to one app, with their measured sizes.
function Applications.data(model, bundleId, name)
	local folders, bytes = {}, 0
	if not bundleId and not name then return folders, bytes end
	local lowerId, lowerName = bundleId and bundleId:lower(), name and name:lower()
	for _, source in ipairs(Applications.dataSources) do
		local root = model.resources:find(source.id)
		for _, child in ipairs(root and model.breakdowns[source.id] or {}) do
			local candidate = child.name:lower()
			local owned = (source.byId and lowerId and (candidate == lowerId or candidate:sub(1, #lowerId + 1) == lowerId .. "."))
				or (source.contains and lowerId and candidate:find(lowerId, 1, true) ~= nil)
				or (source.byName and lowerName and candidate == lowerName)
			if owned and child.directory then
				local childBytes = math.floor((child.kb or 0) * 1024 + 0.5)
				bytes = bytes + childBytes
				table.insert(folders, {name = child.name, label = source.label, path = root.path .. "/" .. child.name, bytes = childBytes})
			end
		end
	end
	table.sort(folders, function(a, b) return a.bytes > b.bytes end)
	return folders, bytes
end

-- Rows for the Applications page. `info` maps a bundle path to
-- `{bundleId, version, lastUsed}` from the service; missing info leaves the
-- app listed with its bundle size only.
function Applications.rows(model, info, filter, query, now)
	now = now or os.time()
	local needle, rows = (query or ""):lower(), {}
	for _, bundle in ipairs(Applications.bundles(model)) do
		local m = model.measurements[bundle.id] or {}
		local details = info and info[bundle.path] or {}
		local name = bundle.name:gsub("%.app$", "")
		local folders, dataBytes = Applications.data(model, details.bundleId, name)
		local appBytes = m.bytes or 0
		local unused = details.lastUsed and (now - details.lastUsed) > Applications.unusedDays * 86400
		local row = {id = bundle.id, resourceId = bundle.id, name = name, path = bundle.path, bundleId = details.bundleId,
			appIcon = details.bundleId, fileIcon = bundle.path, icon = "app.fill", color = "systemBlue",
			appBytes = appBytes, dataBytes = dataBytes, bytes = appBytes + dataBytes, folders = folders,
			lastUsed = details.lastUsed, unused = unused == true, calculating = m.status == "calculating",
			detail = details.lastUsed and Files.age(details.lastUsed, now) or (info and "Never opened" or "—")}
		row.size = row.calculating and "Calculating…" or Model.size(row.bytes)
		row.subtitle = (details.version and ("Version " .. details.version .. " · ") or "") .. "App " .. Model.size(appBytes)
			.. (dataBytes > 0 and (" · Data " .. Model.size(dataBytes)) or "")
		local visible = filter ~= "Unused for 6 months" or row.unused or (info and not details.lastUsed)
		if visible and (needle == "" or (name .. " " .. (details.bundleId or "")):lower():find(needle, 1, true)) then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		local left, right = a.bytes, b.bytes
		if filter == "Most data" then left, right = a.dataBytes, b.dataBytes end
		if left ~= right then return left > right end
		return a.name:lower() < b.name:lower()
	end)
	local largest = 0
	for _, row in ipairs(rows) do largest = math.max(largest, filter == "Most data" and row.dataBytes or row.bytes) end
	for _, row in ipairs(rows) do
		row.relative = largest > 0 and (filter == "Most data" and row.dataBytes or row.bytes) / largest or 0
		row.shareText = ""
	end
	return rows
end

-- Data folders named like a bundle identifier that no installed app claims:
-- what AppCleaner and CleanMyMac call leftovers. `installed` is the list of
-- bundle identifiers Spotlight knows; without it nothing is reported, since
-- an unknown app is not evidence of an uninstalled one. Apple's own
-- identifiers are never listed.
function Applications.leftovers(model, installed, query)
	if not installed then return nil end
	local known = {}
	for _, id in ipairs(installed) do known[id:lower()] = true end
	local function claimed(name)
		local lower = name:lower():gsub("^group%.", "")
		if known[lower] then return true end
		-- Extensions and helpers use the host app's identifier as a prefix.
		for id in pairs(known) do
			if lower:sub(1, #id + 1) == id .. "." or id:sub(1, #lower + 1) == lower .. "." then return true end
		end
		return false
	end
	local needle, rows = (query or ""):lower(), {}
	for _, source in ipairs(Applications.dataSources) do
		local root = model.resources:find(source.id)
		for _, child in ipairs(root and model.breakdowns[source.id] or {}) do
			local bytes = math.floor((child.kb or 0) * 1024 + 0.5)
			if child.directory and bytes >= Applications.leftoverMinimum and reverseDNS(child.name) and not apple(child.name)
				and not claimed(child.name) and (needle == "" or child.name:lower():find(needle, 1, true)) then
				table.insert(rows, {id = root.path .. "/" .. child.name, path = root.path .. "/" .. child.name, name = child.name,
					subtitle = source.label .. " · no installed app uses this identifier", bytes = bytes, size = Model.size(bytes),
					icon = "questionmark.folder.fill", color = "systemGray", detail = source.label})
			end
		end
	end
	table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.name < b.name end)
	local largest = rows[1] and rows[1].bytes or 0
	for _, row in ipairs(rows) do row.relative = largest > 0 and row.bytes / largest or 0; row.shareText = "" end
	return rows
end

-- A leftover may be moved to the Trash only while it is still an unclaimed,
-- measured folder directly inside one of the data sources.
function Applications.validateLeftover(model, installed, path)
	for _, row in ipairs(Applications.leftovers(model, installed) or {}) do
		if row.path == path then return true end
	end
	return false, {code = "not_leftover", message = "This folder is no longer an unclaimed leftover. Refresh and review it again."}
end

-- Seconds since 1970 for a UTC civil date, independent of the local zone.
local function utc(year, month, day, hour, minute, second)
	local y = month <= 2 and year - 1 or year
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return ((era * 146097 + doe - 719468) * 86400) + hour * 3600 + minute * 60 + second
end
-- `mdls -raw -name kMDItemLastUsedDate a b …` prints one value per file,
-- separated by NUL, as "2026-09-20 16:20:00 +0000" or "(null)".
function Applications.parseLastUsed(output, paths)
	local result, index = {}, 0
	for value in ((output or "") .. "\0"):gmatch("([^%z]*)%z") do
		index = index + 1
		local path = paths[index]
		if not path then break end
		local y, mo, d, h, mi, s, sign, oh, om = value:match("^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+) ([%+%-])(%d%d)(%d%d)")
		if y then
			local offset = (tonumber(oh) * 3600 + tonumber(om) * 60) * (sign == "-" and -1 or 1)
			result[path] = utc(tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)) - offset
		end
	end
	return result
end

function Applications.summary(rows, leftovers)
	local apps, data, unused, unusedBytes = 0, 0, 0, 0
	for _, row in ipairs(rows) do
		apps = apps + row.appBytes; data = data + row.dataBytes
		if row.unused then unused = unused + 1; unusedBytes = unusedBytes + row.bytes end
	end
	local leftoverBytes = 0
	for _, row in ipairs(leftovers or {}) do leftoverBytes = leftoverBytes + row.bytes end
	return {count = #rows, apps = apps, data = data, unused = unused, unusedBytes = unusedBytes,
		leftovers = leftovers and #leftovers or nil, leftoverBytes = leftoverBytes}
end

return Applications
