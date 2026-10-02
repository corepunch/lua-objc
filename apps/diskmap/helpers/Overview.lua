local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local Categories = require("apps.diskmap.helpers.Categories")
local Status = require("apps.diskmap.helpers.Status")
local Overview = {}

-- The donut draws at most this many named categories; smaller measured
-- categories share one "Other categories" sector so thin slivers stay legible,
-- and the legend beside it stays one short column.
local CHART = {categories = 5}

local percent = Format.percent

-- The id of the sector and legend row that stand for every category too
-- small to draw on its own.
Overview.folded = "#other"

-- Volume summary for the hero card. Capacity numbers come from the system
-- volume query; measured totals come from the ledger and never replace them.
function Overview.summary(disk, capacity)
	local model = Model.db
	local result = {measured = Format.size(Store.total(model))}
	if not disk or not disk.totalKb or disk.totalKb <= 0 then
		result.available = false
		result.used, result.total, result.free = "—", "Capacity unavailable", "—"
		result.caption = "Capacity unavailable"
		return result
	end
	local total, free = disk.totalKb * 1024, disk.freeKb * 1024
	result.available = true
	result.used, result.total, result.free = Format.size(total - free), Format.size(total), Format.size(free)
	result.usedPercent = percent(total - free, total)
	result.caption = "of " .. result.total .. " used"
	result.subtitle = result.free .. " free of " .. result.total
	result.short = result.subtitle
	-- Finder's "available" adds purgeable storage macOS will release on demand.
	-- The window subtitle has room for one number, so it takes Finder's; the
	-- Overview card states free and available apart.
	if capacity and capacity.important and capacity.important > free then
		result.availableText = Format.size(capacity.important)
		result.subtitle = result.free .. " free · " .. result.availableText .. " available of " .. result.total
		result.short = result.availableText .. " available of " .. result.total
	end
	result.lowSpace = free / total < 0.1
	return result
end

-- Donut marks and legend rows. Marks carry their segment's id and size so
-- the chart can name the sector under the pointer. The ring is the whole volume: measured
-- categories in their colors, then the unattributed residual, then free space
-- as the empty track. Categories.distribution already refuses to draw a
-- partition when measured allocation exceeds used capacity.
function Overview.chart(disk)
	local model = Model.db
	local segments, explanation = Categories.distribution(disk)
	local named, rest, residual, free = {}, nil, nil, nil
	for _, segment in ipairs(segments) do
		if segment.id == "free" then free = segment
		elseif segment.id == "unreconciled" then residual = segment
		elseif segment.bytes > 0 then table.insert(named, segment) end
	end
	local total = disk and disk.totalKb and disk.totalKb * 1024 or 0
	local used = free and total - free.bytes or 0
	local marks, legend = {}, {}
	for index, segment in ipairs(named) do
		if index <= CHART.categories then
			table.insert(marks, {id = segment.id, value = segment.bytes, color = segment.color, label = segment.name})
			table.insert(legend, {id = segment.id, name = segment.name, color = segment.color, size = segment.size,
				share = percent(segment.bytes, used)})
		else
			rest = rest or {bytes = 0, count = 0}
			rest.bytes = rest.bytes + segment.bytes; rest.count = rest.count + 1
		end
	end
	if rest then
		-- The folded categories are "#other", like a map level's folded
		-- remainder: "other" is a category of its own.
		table.insert(marks, {id = Overview.folded, value = rest.bytes, color = "systemGray", label = "Other categories"})
		table.insert(legend, {id = Overview.folded, name = rest.count .. " more categories", color = "systemGray",
			size = Format.size(rest.bytes), share = percent(rest.bytes, used)})
	end
	if residual and residual.bytes > 0 then
		table.insert(marks, {id = "unreconciled", value = residual.bytes, color = "tertiary", label = residual.name})
	end
	if free and free.bytes > 0 then
		table.insert(marks, {id = "free", value = free.bytes, color = "quaternaryLabel", label = "Free"})
	end
	-- `detail` is the line under the ring for the sector under the pointer,
	-- as the Map names its hovered node. Used space is shared out of what is
	-- used, like the legend; free space out of the whole disk.
	local summary = {}
	for _, mark in ipairs(marks) do
		mark.size = Format.size(mark.value)
		mark.detail = mark.label .. " · " .. mark.size .. " · "
			.. (mark.id == "free" and (percent(mark.value, total) .. " of disk") or percent(mark.value, used))
		table.insert(summary, mark.label .. " " .. mark.size)
	end
	return {marks = marks, legend = legend, explanation = explanation,
		residual = residual and residual.bytes > 0 and residual.size or nil,
		accessibilityLabel = #summary > 0 and ("Storage by category: " .. table.concat(summary, ", ")) or explanation}
end

-- Top-level category rows with a share of used capacity. The level bar
-- compares each category with the largest one so small categories stay
-- readable next to a dominant one.
function Overview.categories(disk, query)
	local model = Model.db
	local rows = Categories.rows(nil, query)
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	local largest, order = 0, {}
	for index, row in ipairs(rows) do
		row.children = nil
		order[row] = index
		largest = math.max(largest, row.bytes or 0)
	end
	-- Unmeasured categories keep catalog order after the measured ones.
	table.sort(rows, function(a, b)
		if (a.bytes or -1) ~= (b.bytes or -1) then return (a.bytes or -1) > (b.bytes or -1) end
		return order[a] < order[b]
	end)
	for _, row in ipairs(rows) do
		row.shareText = row.bytes and percent(row.bytes, used) or ""
		row.relative = row.bytes and largest > 0 and row.bytes / largest or nil
	end
	return rows
end

-- The part of used capacity that no file scan can attribute, split into what
-- macOS reports separately: purgeable storage, local snapshots and locations
-- Diskmap could not read. Sizes appear only where macOS provides them.
-- `mediaExcluded` names the Photos, Music and TV libraries while they are
-- left out of the scan, so a disk that is full of photos says where they are.
-- `readErrors` counts every refused location; `protected` (from
-- Overview.protected) the ones macOS keeps from every app, which no
-- permission can open.
function Overview.hidden(disk, capacity, snapshotCount, readErrors, cloudBytes, cloudFiles, mediaExcluded, protected)
	local rows = {}
	if mediaExcluded then
		table.insert(rows, {id = "media", icon = "photo.on.rectangle", title = "Photos, Music & TV libraries",
			value = "Not scanned", detail = "Left out until you turn on Include media libraries in Settings"})
	end
	if cloudFiles and cloudFiles > 0 then
		table.insert(rows, {id = "icloud", icon = "icloud", title = "In iCloud only",
			value = Format.size(cloudBytes or 0), detail = Format.count(cloudFiles) .. " evicted files use no space here; opening one downloads it"})
	end
	if disk and capacity and capacity.important and capacity.important > disk.freeKb * 1024 then
		table.insert(rows, {id = "purgeable", icon = "arrow.3.trianglepath", title = "Purgeable",
			value = Format.size(capacity.important - disk.freeKb * 1024),
			detail = "Snapshots, iCloud copies and caches macOS frees when space is needed"})
	end
	if snapshotCount and snapshotCount > 0 then
		table.insert(rows, {id = "snapshots", icon = "clock.arrow.circlepath", title = "Local snapshots",
			value = Format.count(snapshotCount), detail = "Hold deleted files' blocks; their size cannot be measured per file"})
	end
	local refused = protected and protected.refused or 0
	local private = (readErrors or 0) - refused
	if private > 0 then
		table.insert(rows, {id = "unreadable", icon = "lock", title = "Unreadable locations",
			value = Format.count(private), detail = "Full Disk Access lets Diskmap measure them"})
	end
	if protected and protected.count > 0 then
		table.insert(rows, {id = "protected", icon = "lock.shield", title = "Protected by macOS",
			value = Format.count(protected.count), detail = protected.detail})
	end
	return rows
end

-- Locations macOS keeps from every app: the known ones present here
-- (knowledge/Filesystem), which no walk enters, and those the scanner found
-- refusing every process (`refused`, part of the scan's error total). With
-- Full Disk Access on, every remaining refusal is one no permission lifts.
-- Their space stays in the used total, so it reads as not attributed.
function Overview.protected(fullDiskAccess)
	local model = Model.db
	local names, seen = {}, {}
	for _, location in ipairs(model.protected or {}) do
		local name = location.feature or location.name
		if not seen[name] then seen[name] = true; table.insert(names, name) end
	end
	local scan = model.scan or {}
	local refused = fullDiskAccess == true and (scan.errors or 0) or (scan.protected or 0)
	local count = #(model.protected or {}) + refused
	local detail = "No app can read these, with any permission; their space counts as not attributed"
	if #names > 0 then detail = table.concat(names, ", ") .. (refused > 0 and " and other system folders" or "") .. ". " .. detail end
	return {count = count, refused = refused, names = names, detail = detail}
end

Overview.protectedNames = 4
-- What the Overview's "not measured" card explains: how much used space no
-- category holds, and each reason, with the one action that helps where
-- there is one. `options`: fullDiskAccess, diskAccess (false while the App
-- Sandbox hides the startup disk), snapshotCount, mediaExcluded.
function Overview.unmeasured(disk, options)
	local model = Model.db
	options = options or {}
	local items = {}
	local protected = Overview.protected(options.fullDiskAccess)
	if protected.count > 0 then
		-- A few names say what kind of folders these are; macOS Folders lists them all.
		local shown = {}
		for index = 1, math.min(#protected.names, Overview.protectedNames) do table.insert(shown, protected.names[index]) end
		local rest = #protected.names - #shown
		local named = #shown > 0 and ("Including " .. table.concat(shown, ", ") .. ((rest > 0 or protected.refused > 0) and ", and other system folders" or "") .. ". ") or ""
		table.insert(items, {id = "protected", icon = "lock.shield.fill", color = "systemGray", title = "Protected by macOS",
			value = Format.count(protected.count) .. (protected.count == 1 and " location" or " locations"),
			detail = named .. "No app can read these, whatever permission it has, so their size cannot be measured."})
	end
	local privacy = options.fullDiskAccess == false and Overview.unreadable() or {paths = {}, total = 0, more = 0}
	if privacy.total > 0 then
		-- Without the disk, Full Disk Access cannot help: the sandbox refuses first.
		local disk = options.diskAccess == false
		table.insert(items, {id = "privacy", icon = "lock.fill", color = "systemOrange",
			title = disk and "Needs access to your disk" or "Needs Full Disk Access",
			value = Format.count(privacy.total) .. (privacy.total == 1 and " location" or " locations"),
			detail = disk and "Apps from the App Store see only what you allow. Allow your startup disk, and Diskmap can measure these."
				or "Diskmap can measure these once Full Disk Access is on.",
			paths = privacy.paths, more = privacy.more > 0 and ("and " .. Format.count(privacy.more) .. " more") or nil, grant = true,
			grantTitle = disk and "Allow Access to Disk…" or "Open Full Disk Access Settings…"})
	end
	if (options.snapshotCount or 0) > 0 then
		table.insert(items, {id = "snapshots", icon = "clock.arrow.circlepath", color = "systemBlue", title = "Local snapshots",
			value = Format.count(options.snapshotCount),
			detail = "They keep the blocks of files you deleted until macOS removes them. No file scan can say how much each holds."})
	end
	if options.mediaExcluded then
		table.insert(items, {id = "media", icon = "photo.on.rectangle", color = "systemPink", title = "Photos, Music & TV libraries",
			value = "Not scanned", detail = "Left out of the scan. Turn on Include media libraries in Settings to measure them."})
	end
	local residual
	for _, segment in ipairs((Categories.distribution(disk))) do
		if segment.id == "unreconciled" and segment.bytes > 0 then residual = segment end
	end
	local summary = residual and (residual.size .. " of used space is in no category. It is made up of what follows, and of file system bookkeeping.")
		or "Everything Diskmap could not measure, and why."
	return {items = items, summary = summary, notAttributed = residual and residual.size or nil}
end

-- The folders the last scan could not read, for the notice that offers Full
-- Disk Access: at most `limit` paths, shown from the home folder, and how
-- many more there were. The scan keeps the first thousand paths and goes on
-- counting, so the count of the rest comes from its error total: the notice
-- and the "Unreadable locations" row then name the same number. Folders
-- System Integrity Protection guards are left out: Full Disk Access cannot
-- open them, so the notice would promise what it cannot deliver.
Overview.unreadableLimit = 6
function Overview.unreadable(limit)
	local model = Model.db
	limit = limit or Overview.unreadableLimit
	local paths, seen, total = {}, {}, 0
	local home = model.home or ""
	for _, issue in ipairs(model.scan and model.scan.issues or {}) do
		local path = issue.path
		if type(path) == "string" and not issue.protected and not seen[path] then
			seen[path] = true
			total = total + 1
			if #paths < limit then
				if home ~= "" and path:sub(1, #home + 1) == home .. "/" then path = "~" .. path:sub(#home + 1) end
				table.insert(paths, path)
			end
		end
	end
	total = math.max(total, math.floor(model.scan and (model.scan.errors or 0) - (model.scan.protected or 0) or 0))
	return {paths = paths, more = math.max(0, total - #paths), moreText = Format.count(math.max(0, total - #paths)), total = total}
end

-- Headline for the Clean Up call to action: the same estimate Clean Up and
-- its sidebar badge state, computed by the same presentation, so the three
-- never name different numbers. What could be recovered leads; bytes that
-- only a person can judge follow as bytes to review, never added to it.
-- `sources` is what other pages measured (the Applications summary).
function Overview.reclaim(sources)
	local model = Model.db
	local data = require("apps.diskmap.helpers.Recommendations").presentation("", sources or {})
	local result = {count = data.count, eligible = data.eligibleBytes, review = data.reviewBytes, top = data.lead and data.lead.name or nil}
	if data.count == 0 then
		result.title = "No cleanup suggestions yet"
		result.detail = "Suggestions appear once measured caches or build data exceed their review thresholds."
	elseif data.eligibleBytes > 0 then
		result.title = Format.size(data.eligibleBytes) .. " could recover"
		result.detail = data.count .. (data.count == 1 and " suggestion" or " suggestions")
			.. (data.reviewBytes > 0 and (" · " .. Format.size(data.reviewBytes) .. " more to review") or "")
			.. (result.top and (" · start with " .. result.top) or "")
	else
		-- Nothing is proven recoverable yet; lead with what can be reviewed
		-- rather than a zero.
		result.title = Format.size(data.reviewBytes) .. " to review"
		result.detail = data.count .. (data.count == 1 and " suggestion" or " suggestions") .. " · nothing recoverable without review"
	end
	return result
end

local function ancestry(row)
	local names, parent = {}, row:parent()
	while parent do table.insert(names, 1, parent.name); parent = parent:parent() end
	return table.concat(names, " › ")
end

-- The largest individually measured resources across every category: the
-- quickest answer to "what is eating my storage?". A row opens by its own id,
-- wherever its location sends it.
function Overview.largest(disk, limit, query)
	local model = Model.db
	local rows, needle = {}, (query or ""):lower()
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	for _, row in ipairs(Locations:leaves()) do
		local m = model.measurements[row.id]
		if m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) > 0 then
			local owner = ancestry(row)
			if needle == "" or (row.name .. " " .. owner .. " " .. (row.path or "")):lower():find(needle, 1, true) then
				local root = row
				while root:parent() do root = root:parent() end
				table.insert(rows, {id = row.id, rootId = root.id,
					name = row.name, subtitle = owner,
					bytes = m.bytes,
					share = used and m.bytes / used or 0, shareText = percent(m.bytes, used),
					icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
					impact = row.policy == "Essential" and "Keep" or row.policy == "Rebuildable" and "Rebuildable"
						or row.policy == "System managed" and "System managed" or "Review",
					kept = row:isKept()})
				rows[#rows].detail = rows[#rows].kept and "Kept" or rows[#rows].impact
				Format.sizeLabel(rows[#rows], m.status, m.bytes)
				Status.apply(rows[#rows])
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	if limit then while #rows > limit do table.remove(rows) end end
	-- Bars compare items with the largest one, like a ranked bar chart; the
	-- label keeps the share of used capacity.
	for _, row in ipairs(rows) do row.relative = row.bytes / rows[1].bytes end
	return rows
end

return Overview
