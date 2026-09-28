local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Status = require("apps.diskmap.models.Status")
local Overview = {}

-- The donut draws at most this many named categories; smaller measured
-- categories share one "Other categories" sector so thin slivers stay legible.
local CHART = {categories = 7}

local percent = Model.percent

-- Volume summary for the hero card. Capacity numbers come from the system
-- volume query; measured totals come from the ledger and never replace them.
function Overview.summary(model, disk, capacity)
	local result = {measured = Model.size(Model.total(model))}
	if not disk or not disk.totalKb or disk.totalKb <= 0 then
		result.available = false
		result.used, result.total, result.free = "—", "Capacity unavailable", "—"
		result.caption = "Capacity unavailable"
		return result
	end
	local total, free = disk.totalKb * 1024, disk.freeKb * 1024
	result.available = true
	result.used, result.total, result.free = Model.size(total - free), Model.size(total), Model.size(free)
	result.usedPercent = percent(total - free, total)
	result.caption = "of " .. result.total .. " used"
	result.subtitle = result.free .. " free of " .. result.total
	-- Finder's "available" adds purgeable storage macOS will release on demand.
	if capacity and capacity.important and capacity.important > free then
		result.availableText = Model.size(capacity.important)
		result.subtitle = result.free .. " free · " .. result.availableText .. " available of " .. result.total
	end
	result.lowSpace = free / total < 0.1
	return result
end

-- Donut marks and legend rows. The ring is the whole volume: measured
-- categories in their colors, then the unattributed residual, then free space
-- as the empty track. Categories.distribution already refuses to draw a
-- partition when measured allocation exceeds used capacity.
function Overview.chart(model, disk)
	local segments, explanation = Categories.distribution(model, disk)
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
			table.insert(marks, {value = segment.bytes, color = segment.color, label = segment.name})
			table.insert(legend, {id = segment.id, name = segment.name, color = segment.color, size = segment.size,
				share = percent(segment.bytes, used)})
		else
			rest = rest or {bytes = 0, count = 0}
			rest.bytes = rest.bytes + segment.bytes; rest.count = rest.count + 1
		end
	end
	if rest then
		table.insert(marks, {value = rest.bytes, color = "systemGray", label = "Other categories"})
		table.insert(legend, {id = "other", name = rest.count .. " more categories", color = "systemGray",
			size = Model.size(rest.bytes), share = percent(rest.bytes, used)})
	end
	if residual and residual.bytes > 0 then
		table.insert(marks, {value = residual.bytes, color = "tertiary", label = "Not attributed"})
	end
	if free and free.bytes > 0 then
		table.insert(marks, {value = free.bytes, color = "quaternaryLabel", label = "Free"})
	end
	local summary = {}
	for _, mark in ipairs(marks) do table.insert(summary, mark.label .. " " .. Model.size(mark.value)) end
	return {marks = marks, legend = legend, explanation = explanation,
		residual = residual and residual.bytes > 0 and residual.size or nil,
		accessibilityLabel = #summary > 0 and ("Storage by category: " .. table.concat(summary, ", ")) or explanation}
end

-- Top-level category rows with a share of used capacity. The level bar
-- compares each category with the largest one so small categories stay
-- readable next to a dominant one.
function Overview.categories(model, disk, query)
	local rows = Categories.rows(model, nil, query)
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
function Overview.hidden(disk, capacity, snapshotCount, readErrors, cloudBytes, cloudFiles)
	local rows = {}
	if cloudFiles and cloudFiles > 0 then
		table.insert(rows, {id = "icloud", icon = "icloud", title = "In iCloud only",
			value = Model.size(cloudBytes or 0), detail = Model.count(cloudFiles) .. " evicted files use no space here; opening one downloads it"})
	end
	if disk and capacity and capacity.important and capacity.important > disk.freeKb * 1024 then
		table.insert(rows, {id = "purgeable", icon = "arrow.3.trianglepath", title = "Purgeable",
			value = Model.size(capacity.important - disk.freeKb * 1024),
			detail = "Snapshots, iCloud copies and caches macOS frees when space is needed"})
	end
	if snapshotCount and snapshotCount > 0 then
		table.insert(rows, {id = "snapshots", icon = "clock.arrow.circlepath", title = "Local snapshots",
			value = tostring(snapshotCount), detail = "Hold deleted files' blocks; their size cannot be measured per file"})
	end
	if readErrors and readErrors > 0 then
		table.insert(rows, {id = "unreadable", icon = "lock", title = "Unreadable locations",
			value = tostring(readErrors), detail = "Full Disk Access lets Diskmap measure them"})
	end
	return rows
end

-- The folders the last scan could not read, for the notice that offers Full
-- Disk Access: at most `limit` paths, shown from the home folder, and how
-- many more there were.
Overview.unreadableLimit = 6
function Overview.unreadable(model, limit)
	limit = limit or Overview.unreadableLimit
	local paths, seen, total = {}, {}, 0
	local home = model.home or ""
	for _, issue in ipairs(model.scan and model.scan.issues or {}) do
		local path = issue.path
		if type(path) == "string" and not seen[path] then
			seen[path] = true
			total = total + 1
			if #paths < limit then
				if home ~= "" and path:sub(1, #home + 1) == home .. "/" then path = "~" .. path:sub(#home + 1) end
				table.insert(paths, path)
			end
		end
	end
	return {paths = paths, more = math.max(0, total - #paths), total = total}
end

-- Headline for the Clean Up call to action. Rebuildable and review-first
-- candidates stay separate; they are never summed into one "safe" number.
function Overview.reclaim(model)
	local rebuildable, review, count = 0, 0, 0
	for _, row in ipairs(Cleanup.suggestions(model)) do
		count = count + 1
		if row.impact == "Safe/rebuildable" then rebuildable = rebuildable + (row.bytes or 0)
		else review = review + (row.bytes or 0) end
	end
	local result = {count = count, rebuildable = rebuildable, review = review}
	if count == 0 then
		result.title = "No cleanup suggestions yet"
		result.detail = "Suggestions appear once measured caches or build data exceed their review thresholds."
	elseif rebuildable > 0 then
		result.title = Model.size(rebuildable) .. " rebuildable"
		result.detail = count .. (count == 1 and " suggestion" or " suggestions")
			.. (review > 0 and (" · " .. Model.size(review) .. " more to review") or "")
	else
		-- Nothing is rebuildable yet; lead with what can be reviewed rather
		-- than a zero.
		result.title = Model.size(review) .. " to review"
		result.detail = count .. (count == 1 and " suggestion" or " suggestions") .. " · nothing rebuildable without review"
	end
	return result
end

local function ancestry(row)
	local names, parent = {}, row:getParent()
	while parent do table.insert(names, 1, parent.name); parent = parent:getParent() end
	return table.concat(names, " › ")
end

-- The largest individually measured resources across every category: the
-- quickest answer to "what is eating my storage?". Each row keeps its semantic
-- owner so it opens in the category that manages it.
function Overview.largest(model, disk, limit, query)
	local rows, needle = {}, (query or ""):lower()
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	for _, row in ipairs(model.resources:leaves()) do
		local m = model.measurements[row.id]
		if m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) > 0 then
			local owner = ancestry(row)
			if needle == "" or (row.name .. " " .. owner .. " " .. (row.path or "")):lower():find(needle, 1, true) then
				local root = row
				while root:getParent() do root = root:getParent() end
				table.insert(rows, {id = row.id, rootId = root.id, parentId = row:getParent() and row:getParent().id or row.id,
					name = row.name, subtitle = owner,
					bytes = m.bytes, size = (m.status == "partial" and "≥ " or "") .. Model.size(m.bytes),
					share = used and m.bytes / used or 0, shareText = percent(m.bytes, used),
					icon = row.icon, color = row.color, appIcon = row.appIcon, path = row.path,
					impact = row.policy == "Essential" and "Keep" or row.policy == "Rebuildable" and "Rebuildable"
						or row.policy == "System managed" and "System managed" or "Review",
					kept = row:isKept()})
				rows[#rows].detail = rows[#rows].kept and "Kept" or rows[#rows].impact
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
