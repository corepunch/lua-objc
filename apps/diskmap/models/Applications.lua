local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
local Leftovers = require("apps.diskmap.helpers.Leftovers")
-- The installed applications: discovered `.app` locations, plus catalog
-- apps such as Xcode when they exist; a bundle the scan found missing is not
-- installed. What the service tells about them lives in the store beside
-- them: `applicationInfo` maps a bundle path to {bundleId, displayName,
-- version, lastUsed, running}, and `installedBundleIds` lists every bundle
-- identifier Spotlight knows. Missing info leaves an app listed with its
-- bundle size only.
local Applications = Model:extend("applications", {primaryKey = "path", source = function(db)
	local rows = {}
	for _, row in ipairs(Locations:leaves()) do
		local m = db.measurements[row.id]
		local missing = m and m.status == "complete" and (m.bytes or 0) == 0
		if row.path and row.path:match("%.app$") and not missing then table.insert(rows, row) end
	end
	return rows
end})

-- An app's data lives outside its bundle, in folders named by its bundle
-- identifier (or, for Application Support, sometimes its name). These are
-- the catalog locations whose immediate children the scan already measured.
Applications.dataSources = {
	{id = "app-containers", label = "Container", byId = true},
	{id = "group-containers", label = "Group container", contains = true},
	{id = "support", label = "Application Support", byId = true, byName = true},
	{id = "user-caches", label = "Caches", byId = true},
}
Applications.filters = Model.enum({"All", "Unused for 6 months", "Most data"})
Applications.unusedDays = 180
-- Folders smaller than this are not worth listing as possible leftovers.
Applications.leftoverMinimum = 50e6


-- The data folders that belong to one app, with their measured sizes.
function Applications:data(bundleId, name)
	local model = Model.db
	local folders, bytes = {}, 0
	if not bundleId and not name then return folders, bytes end
	local lowerId, lowerName = bundleId and bundleId:lower(), name and name:lower()
	local supportNames = Leftovers.supportNames(bundleId) or {}
	for _, source in ipairs(Applications.dataSources) do
		local root = Locations:find(source.id)
		for _, child in ipairs(root and model.breakdowns[source.id] or {}) do
			local candidate = child.name:lower()
			local owned = (source.byId and lowerId and (candidate == lowerId or candidate:sub(1, #lowerId + 1) == lowerId .. "."))
				or (source.contains and lowerId and candidate:find(lowerId, 1, true) ~= nil)
				or (source.byName and ((lowerName and candidate == lowerName) or supportNames[candidate]))
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

-- Rows for the Applications page.
function Applications:rows(filter, query, now)
	local model = Model.db
	local info = model.applicationInfo
	now = now or os.time()
	local needle, rows = (query or ""):lower(), {}
	for _, bundle in ipairs(Applications:all()) do
		local m = model.measurements[bundle.id] or {}
		local details = info and info[bundle.path] or {}
		-- An app is called what Finder calls it. A catalog row's own title ("Xcode & bundled
		-- SDKs") describes a category, not the app.
		local fileName = (bundle.path:match("([^/]+)%.app$")) or bundle.name:gsub("%.app$", "")
		-- Finder shows the file name; a name that is only an identifier
		-- ("logioptionsplus") gives way to the bundle's display name.
		local raw = not fileName:find("[%u%s]")
		local name = raw and details.displayName or fileName
		local folders, dataBytes = Applications:data(details.bundleId, fileName)
		local appBytes = m.bytes or 0
		-- A running app is in use now, whatever its recorded date.
		local unused = details.lastUsed and not details.running and (now - details.lastUsed) > Applications.unusedDays * 86400
		local row = {id = bundle.id, resourceId = bundle.id, name = name, path = bundle.path, bundleId = details.bundleId,
			appIcon = details.bundleId, fileIcon = bundle.path, icon = "app.fill", color = "systemBlue",
			appBytes = appBytes, dataBytes = dataBytes, bytes = appBytes + dataBytes, folders = folders,
			lastUsed = details.lastUsed, running = details.running == true, unused = unused == true,
			-- A missing date is not evidence of inactivity: Spotlight may simply not
			-- track the app. It stays unknown and is excluded from every
			-- inactivity filter, total and suggestion.
			usageUnknown = details.lastUsed == nil,
			detail = details.running and "Running now" or details.lastUsed and Format.used(Format.age(details.lastUsed, now)) or (info and "Last use unknown" or "—")}
		row.size = Format.size(row.bytes)
		row.subtitle = (details.version and ("Version " .. details.version .. " · ") or "") .. "App " .. Format.size(appBytes)
			.. (dataBytes > 0 and (" · Data " .. Format.size(dataBytes)) or "")
		local visible = filter ~= "Unused for 6 months" or row.unused
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

-- Data folders that no installed app claims: what AppCleaner and CleanMyMac
-- call leftovers. Without the bundle identifiers Spotlight knows
-- (`installedBundleIds`) nothing is reported, since an unknown app is not
-- evidence of an uninstalled one. Installed bundles found by the scan add
-- their names, so "Google" or "Code" in Application Support stay claimed.
-- Each row carries a confidence tier (see helpers/Leftovers.lua): only High
-- means no app from that vendor is installed. Apple's own data is never listed.
function Applications:leftovers(query)
	local model = Model.db
	local installed = model.installedBundleIds
	if not installed then return nil end
	local apps = {}
	for _, id in ipairs(installed) do table.insert(apps, {bundleId = id}) end
	for _, bundle in ipairs(Applications:all()) do table.insert(apps, {name = bundle.name}) end
	local index = Leftovers.index(apps)
	local needle, rows = (query or ""):lower(), {}
	for _, source in ipairs(Applications.dataSources) do
		local root = Locations:find(source.id)
		for _, child in ipairs(root and model.breakdowns[source.id] or {}) do
			local bytes = math.floor((child.kb or 0) * 1024 + 0.5)
			local tier = child.directory and bytes >= Applications.leftoverMinimum and Leftovers.classify(child.name, source.byName, index)
			if tier and (needle == "" or child.name:lower():find(needle, 1, true)) then
				local info = Leftovers.tiers[tier]
				table.insert(rows, {id = root.path .. "/" .. child.name, path = root.path .. "/" .. child.name, name = child.name,
					subtitle = source.label .. " · " .. info.label, bytes = bytes, size = Format.size(bytes),
					tier = tier, rank = info.rank, confidence = info.confidence, reason = info.label, source = source.label,
					icon = "questionmark.folder.fill", color = tier == "high" and "systemPink" or "systemGray", detail = info.confidence})
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.name < b.name
	end)
	local largest = 0
	for _, row in ipairs(rows) do largest = math.max(largest, row.bytes) end
	for _, row in ipairs(rows) do row.relative = largest > 0 and row.bytes / largest or 0; row.shareText = "" end
	return rows
end

-- A leftover may be moved to the Trash only while it is still an unclaimed,
-- measured folder directly inside one of the data sources.
function Applications:validateLeftover(path)
	for _, row in ipairs(Applications:leftovers() or {}) do
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
		-- The tile counts what the Unused filter lists: apps with a known
		-- last-use date older than six months. Unknown dates are not counted.
		if row.unused then unused = unused + 1; unusedBytes = unusedBytes + row.bytes end
	end
	-- Only High-confidence leftovers (no app from that vendor is installed) are
	-- counted as removable; the rest are bytes to review.
	local leftoverBytes, highBytes, high = 0, 0, 0
	for _, row in ipairs(leftovers or {}) do
		leftoverBytes = leftoverBytes + row.bytes
		if row.tier == "high" then highBytes = highBytes + row.bytes; high = high + 1 end
	end
	return {count = #rows, apps = apps, data = data, unused = unused, unusedBytes = unusedBytes,
		leftovers = leftovers and #leftovers or nil, leftoverBytes = leftoverBytes, leftoversHigh = high, leftoversHighBytes = highBytes}
end

-- The page's leading decision: leftover data first, because removing it
-- changes nothing an installed app needs; then apps with a known long
-- absence; otherwise where else to look. `hasInfo` is whether Spotlight has
-- told the app about last-use dates yet.
function Applications.decision(summary, unmarkedHigh, markedHigh, hasInfo)
	local data = {id = "decision", icon = "questionmark.folder.fill", color = "systemGray"}
	if not summary.leftovers then
		data.title, data.detail, data.amount, data.amountCaption = "Checking for data left behind by removed apps…", "Diskmap compares data folders with the apps Spotlight knows.", "—", "to review"
	elseif summary.leftovers > 0 then
		data.title = "Review " .. Format.plural(summary.leftovers, "possible leftover folder")
		data.detail = summary.leftoversHigh > 0
			and (Format.plural(summary.leftoversHigh, "folder") .. " " .. (summary.leftoversHigh == 1 and "is" or "are") .. " likely leftovers: no app from that vendor is known to be installed. Review the other unclaimed folders individually.")
			or "No known installed app claims these folders. A name-only match does not prove its app was removed; review each folder individually."
		if summary.leftoversHighBytes > 0 then data.amount, data.amountCaption = Format.size(summary.leftoversHighBytes), "could recover"
		else data.amount, data.amountCaption = Format.size(summary.leftoverBytes), "to review" end
		if unmarkedHigh > 0 then
			data.actionTitle, data.action = "Mark " .. Format.plural(unmarkedHigh, "Likely Leftover"), "markHigh"
		elseif markedHigh > 0 then
			data.actionTitle, data.action = "Review Marked Items…", "reviewMarked"
		end
		data.secondaryTitle = unmarkedHigh > 0 and markedHigh > 0 and "Review Marked Items…" or nil
		data.secondaryAction = "reviewMarked"
	elseif hasInfo and summary.unused > 0 then
		data.icon, data.color = "hourglass", "systemOrange"
		data.title = Format.plural(summary.unused, "app") .. " not opened in six months"
		data.detail = "No leftover data was found. These apps have a known last use over six months ago; uninstall them in the Finder or with their own uninstaller if you no longer need them."
		data.amount, data.amountCaption = Format.size(summary.unusedBytes), "to review"
		data.actionTitle, data.action = "Show Unused Apps", "unusedFilter"
	else
		data.icon, data.color = "checkmark.circle.fill", "systemGreen"
		data.title = "No leftover app data"
		data.detail = "Every data folder belongs to an installed app" .. (hasInfo and ", and no app has gone unused for six months" or "") .. ". Clean Up lists the other places worth reviewing."
		data.amount, data.amountCaption = Format.size(0), "could recover"
		data.actionTitle, data.action = "Open Clean Up", "cleanup"
	end
	return data
end

return Applications
