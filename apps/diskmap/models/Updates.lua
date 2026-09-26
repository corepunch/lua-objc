local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local Updates = {}

-- Storage an update passes through, in the order macOS uses it: downloaded
-- into the asset store, prepared on the Update volume, then staged in Preboot.
Updates.stages = {
	{id = "update-assets", title = "Downloaded updates", icon = "arrow.down.circle",
		detail = "Update payloads in the system asset store. A paused or failed download can stay here until macOS retries or removes it."},
	{id = "update-volume", title = "Prepared update", icon = "shippingbox",
		detail = "The Update volume holds an update while macOS prepares and installs it. It is normally small between updates."},
	{id = "preboot", title = "Preboot", icon = "power",
		detail = "Boot files, security cryptexes and any staged update. Never delete anything here; finishing the update shrinks it."},
}

local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
local function day(year, month, dayOfMonth)
	return string.format("%s %d, %s", MONTHS[tonumber(month)] or month, tonumber(dayOfMonth), year)
end

-- Readable date for a Software Update timestamp: a Unix time from the
-- property-list bridge or a "2026-09-20 16:20:00 +0000" string.
function Updates.formatDate(value)
	if type(value) == "number" then return os.date("%b %e, %Y", math.floor(value)):gsub("  ", " ") end
	if type(value) ~= "string" then return nil end
	local year, month, dayOfMonth = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	return year and day(year, month, dayOfMonth) or nil
end

-- Software Update's own record in /Library/Preferences/com.apple.SoftwareUpdate.plist.
-- It is what macOS last found, not a live check, so the page says when that was.
function Updates.softwareUpdate(plist)
	if type(plist) ~= "table" then
		return {known = false, updates = {}, title = "Software Update status unavailable",
			detail = "Open Software Update to check for updates."}
	end
	local updates = {}
	for _, entry in ipairs(type(plist.RecommendedUpdates) == "table" and plist.RecommendedUpdates or {}) do
		if type(entry) == "table" then
			local name = entry["Display Name"] or entry.Identifier
			if type(name) == "string" then
				table.insert(updates, {name = name, version = type(entry["Display Version"]) == "string" and entry["Display Version"] or ""})
			end
		end
	end
	local checked = Updates.formatDate(plist.LastSuccessfulDate)
	local result = {known = true, updates = updates, checked = checked,
		automaticDownload = plist.AutomaticDownload == true or plist.AutomaticDownload == 1}
	if #updates == 0 then
		result.title = "No updates waiting"
	elseif #updates == 1 then
		result.title = updates[1].name .. " is available"
	else
		result.title = #updates .. " updates are available"
	end
	result.detail = (checked and ("Last checked " .. checked) or "Last check date unknown")
		.. (result.automaticDownload and " · Downloads automatically" or "")
	return result
end

-- Local snapshot identifiers ("com.apple.TimeMachine.2026-09-26-101500.local")
-- as readable rows, newest first.
function Updates.snapshots(dates)
	local rows = {}
	for _, identifier in ipairs(dates or {}) do
		local year, month, dayOfMonth, hour, minute = identifier:match("(%d%d%d%d)%-?(%d%d)%-?(%d%d)%-(%d%d)(%d%d)")
		table.insert(rows, {id = identifier, name = year and (day(year, month, dayOfMonth) .. " at " .. hour .. ":" .. minute) or identifier})
	end
	table.sort(rows, function(a, b) return a.id > b.id end)
	return rows
end

local function sized(model, id)
	local row = Categories.row(model, id)
	if not row then return nil end
	if row.calculating then return "Calculating…" end
	return row.size
end

-- Full macOS installers found in Applications. They are ordinary files the
-- App Store can download again, but Diskmap still only reveals them.
function Updates.installers(model)
	local rows = {}
	for _, row in ipairs(model.resources:leaves()) do
		if row.path and row.name:match("^Install macOS .+%.app$") then
			local m = model.measurements[row.id]
			table.insert(rows, {id = row.id, name = row.name:gsub("%.app$", ""), path = row.path,
				bytes = m and m.bytes, size = m and m.status == "calculating" and "Calculating…" or Model.size(m and m.bytes)})
		end
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

-- Everything the Updates & Snapshots page shows. `snapshotDates` is nil while
-- tmutil has not answered, and false when it failed.
function Updates.presentation(model, plist, snapshotDates)
	local stages = {}
	for index, stage in ipairs(Updates.stages) do
		table.insert(stages, {index = index, id = stage.id, title = stage.title, icon = stage.icon,
			detail = stage.detail, size = sized(model, stage.id) or "Not measured"})
	end
	local snapshots = snapshotDates and Updates.snapshots(snapshotDates) or {}
	local snapshotTitle
	if snapshotDates == nil then snapshotTitle = "Checking local snapshots…"
	elseif snapshotDates == false then snapshotTitle = "Local snapshots could not be listed"
	elseif #snapshots == 0 then snapshotTitle = "No local snapshots"
	else snapshotTitle = #snapshots .. (#snapshots == 1 and " local snapshot" or " local snapshots") end
	return {softwareUpdate = Updates.softwareUpdate(plist), stages = stages,
		installers = Updates.installers(model), snapshots = snapshots, snapshotTitle = snapshotTitle}
end

return Updates
