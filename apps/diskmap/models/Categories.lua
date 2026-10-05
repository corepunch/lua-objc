local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Scans = require("apps.diskmap.models.Scans")
local Format = require("apps.diskmap.helpers.Format")
local Palette = require("apps.diskmap.helpers.Palette")

-- Categories: the catalog's tree of locations with each group's measurement
-- rolled up from its children, the rows every list, chart and map of
-- storage draws. A view of the store, as a database view is of its tables:
-- nothing is stored, the rows are computed from `locations` and
-- `measurements` each time they are asked for.
local Categories
Categories = Model:extend("categories", {source = function() return Categories:rows() end})

local function projection(source)
	return {id = source.id, name = source.name, subtitle = source.subtitle, path = source.path, policy = source.policy,
		action = source.action, consequence = source.consequence, settingsSection = source.settingsSection,
		reviewThreshold = source.reviewThreshold, agent = source.agent, icon = source.icon, color = source.color, appIcon = source.appIcon, fileIcon = source.fileIcon}
end
-- The ring color of each of `rows` (id -> color), claimed largest first so
-- the biggest sectors keep their catalog color and no two sectors of one
-- ring share a hue. The Overview's ring, legend and category rows and the
-- Map's inner ring all ask for it, so a category is one color on a page.
function Categories:hues(rows)
	local sorted = {}
	for _, row in ipairs(rows) do table.insert(sorted, row) end
	table.sort(sorted, function(a, b)
		if (a.bytes or -1) ~= (b.bytes or -1) then return (a.bytes or -1) > (b.bytes or -1) end
		return a.id < b.id
	end)
	local palette, hues = Palette.new(), {}
	for _, row in ipairs(sorted) do hues[row.id] = palette:take(row.color) end
	return hues
end

function Categories:rows(rootId, query)
	local model = Model.db
	local needle = (query or ""):lower()
	local function build(source, inheritedMatch)
		local row = projection(source)
		local matches = inheritedMatch or (source.name .. " " .. source.subtitle .. " " .. (source.path or "")):lower():find(needle, 1, true) ~= nil
		local m = model.measurements[source.id] or {}
		row.bytes, row.status = m.bytes, m.status or "notMeasured"
		if not source:isLeaf() then
			row.children = {}; local total, measured, complete, attempted, calculating, failed, excluded, unsupported, protected = 0, false, true, false, false, false, true, true, true
			local denied = false
			for _, child in ipairs(source:children()) do
				local value, visible = build(child, matches)
				if value.status == "denied" then denied = true end
				if value.bytes then total = total + value.bytes; measured = true end
				if value.status ~= "excluded" then excluded = false end
				if value.status ~= "unsupported" then unsupported = false end
				if value.status ~= "protected" then protected = false end
				if value.status == "failed" then failed = true end
				if value.status == "calculating" then calculating = true end
				if value.status ~= "complete" then complete = false end
				if value.status ~= "notMeasured" then attempted = true end
				if visible then table.insert(row.children, value) end
			end
			row.bytes = measured and total or nil
			-- A group whose readable locations are empty and whose others
			-- could not be read has no access, not "≥ 0 KB".
			if denied and total == 0 and not calculating then row.bytes, measured, complete = nil, false, false end
			-- A group of only system-managed resources (Backups holds just local
			-- snapshots) is system managed, not restricted: nothing was denied.
			-- A group macOS keeps entirely from every app is protected; with
			-- readable siblings its total is a lower bound, like any partial one.
			row.status = excluded and "excluded" or unsupported and "unsupported" or protected and "protected" or calculating and "calculating" or complete and "complete" or measured and "partial" or failed and "failed" or attempted and "denied" or "notMeasured"
			row.expanded = (source.id == "xcode" or source.id == "intelligence")
			row.forceExpanded = needle ~= ""
		end
		Format.sizeLabel(row, row.status, row.bytes)
		row.color = source.color or "secondary"
		row.icon = source.icon or "doc"
		row.kept = model.kept[row.id] == true
		return row, matches or row.children and #row.children > 0
	end
	local source = rootId and Locations:find(rootId)
	local rows = source and (source:isLeaf() and {source} or source:children()) or Locations:roots()
	local result = {}
	for _, row in ipairs(rows) do local value, visible = build(row, false); if visible then table.insert(result, value) end end
	return result
end
-- One rolled-up row (leaf or group) by id, with the same status and size text
-- the category lists show.
function Categories:row(id)
	local resource = Locations:find(id)
	if not resource then return nil end
	local parent = resource:parent()
	for _, row in ipairs(Categories:rows(parent and parent.id or nil)) do
		if row.id == id then return row end
	end
end
-- Categories:row as a plain function, for the helpers that take a lookup
-- (helpers/Guide.lua, Filesystem.lua, Updates.lua).
function Categories.measured(id) return Categories:row(id) end

-- What the helpers that describe known paths need of the store: the home
-- folder, each volume's used space and the lookup above.
function Categories:facts()
	local db = Model.db
	return {home = db.home, volumeUsage = db.volumeUsage, measured = Categories.measured}
end

-- How much of the disk the categories account for, under the category list.
function Categories:coverage(disk)
	local model = Model.db
	local measured = Scans:measured()
	local partial = (model.scan.errors or 0) > 0
	local text = (partial and "At least " or "") .. Format.size(measured) .. " measured"
	if partial then text = text .. string.format(" · %d filesystem read issues", model.scan.errors) end
	if model.scan.running then
		text = text .. " so far · scan in progress"
	elseif disk then
		local difference = (disk.totalKb - disk.freeKb) * 1024 - measured
		text = text .. " · " .. (difference < 0 and "−" or "") .. Format.size(math.abs(difference)) .. " not attributed"
	end
	return text
end
-- Capacity is partitioned into measured categories, a visible residual and free space.
-- Shared-block overcounts cannot be truthfully drawn as a partition of capacity.
function Categories:distribution(disk)
	local model = Model.db
	if not disk or not disk.totalKb or disk.totalKb <= 0 then return {}, "Capacity unavailable" end
	local total, free = disk.totalKb * 1024, disk.freeKb * 1024
	local measured = Scans:measured()
	if measured > total - free then return {}, "Measured allocation exceeds reported usage; shared storage needs reconciliation." end
	local categories = Categories:rows()
	local hues = Categories:hues(categories)
	local segments, assigned = {}, 0
	for _, row in ipairs(categories) do
		local id = row.id
		local bytes = row.bytes or 0; assigned = assigned + bytes
		table.insert(segments, {id = id, name = row.name, color = id == "macos" and "secondary" or hues[id],
			bytes = bytes, weight = bytes / total, size = row.size})
	end
	table.sort(segments, function(left, right)
		if left.bytes ~= right.bytes then return left.bytes > right.bytes end
		return left.id < right.id
	end)
	local other = total - free - assigned
	table.insert(segments, {id = "unreconciled", name = model.scan.running and "Not measured yet" or "Not attributed", color = "tertiary", bytes = other, weight = other / total, size = Format.size(other)})
	table.insert(segments, {id = "free", name = "Free", color = "quaternaryLabel", bytes = free, weight = free / total, size = Format.size(free)})
	if model.scan.running then return segments, "Measurements are still arriving. The gray part includes storage Diskmap has not measured yet; it is not a cleanup estimate." end
	return segments, "Not attributed can include inaccessible files, snapshots and filesystem accounting differences. Category measurements may be partial."
end
-- Flat management rows retain their owner and exact path; totals stay in the ledger.
function Categories:managementRows(rootId, query, filter)
	local model = Model.db
	local result, needle = {}, (query or ""):lower()
	local function visit(row, owner)
		if not row:isLeaf() then
			for _, child in ipairs(row:children()) do visit(child, row.name) end
		else
			local m = model.measurements[row.id] or {}
			local impact = row.policy == "Essential" and "Essential to keep" or row.policy == "Rebuildable" and "Safe/rebuildable" or "Needs review"
			if (not filter or filter == "All" or filter == impact) and (row.name .. " " .. (owner or "") .. " " .. (row.path or "")):lower():find(needle, 1, true) then
				table.insert(result, {id = row.id, name = row.name, subtitle = owner, path = row.path or "System managed", icon = row.icon, color = row.color, appIcon = row.appIcon, fileIcon = row.fileIcon, info = Locations:opensElsewhere(row.id), impact = impact,
					bytes = m.bytes})
				Format.sizeLabel(result[#result], m.status, m.bytes)
			end
		end
	end
	if rootId and Locations:find(rootId) then visit(Locations:find(rootId)) else for _, row in ipairs(Locations:roots()) do visit(row) end end
	return result
end

-- The donut draws at most this many named categories, each in its own hue
-- (Categories:hues), so most of the used space is in color; smaller measured
-- categories share one "Other categories" sector so thin slivers stay legible,
-- and the legend beside it stays one short column.
local CHART = {categories = 7}

local percent = Format.percent

-- The id of the sector and legend row that stand for every category too
-- small to draw on its own.
Categories.folded = "#other"

-- Donut marks and legend rows. Marks carry their segment's id and size so
-- the chart can name the sector under the pointer. The ring is the whole volume: measured
-- categories in their colors, then the unattributed residual, then free space
-- as the empty track. Categories:distribution already refuses to draw a
-- partition when measured allocation exceeds used capacity.
function Categories:chart(disk)
	local segments, explanation = Categories:distribution(disk)
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
		table.insert(marks, {id = Categories.folded, value = rest.bytes, color = "systemGray", label = "Other categories"})
		table.insert(legend, {id = Categories.folded, name = rest.count .. " more categories", color = "systemGray",
			size = Format.size(rest.bytes), share = percent(rest.bytes, used)})
	end
	if residual and residual.bytes > 0 then
		table.insert(marks, {id = "unreconciled", value = residual.bytes, color = "tertiary", label = residual.name})
	end
	if free and free.bytes > 0 then
		table.insert(marks, {id = "free", value = free.bytes, color = "quaternaryLabel", label = "Free"})
	end
	local summary = {}
	for _, mark in ipairs(marks) do
		mark.size = Format.size(mark.value)
		table.insert(summary, mark.label .. " " .. mark.size)
	end
	return {marks = marks, legend = legend, explanation = explanation,
		residual = residual and residual.bytes > 0 and residual.size or nil,
		accessibilityLabel = #summary > 0 and ("Storage by category: " .. table.concat(summary, ", ")) or explanation}
end

-- Top-level category rows with a share of used capacity. The level bar
-- compares each category with the largest one so small categories stay
-- readable next to a dominant one.
function Categories:shares(disk, query)
	local rows = Categories:rows(nil, query)
	local hues = Categories:hues(Categories:rows())
	local used = disk and disk.totalKb and disk.totalKb > 0 and (disk.totalKb - disk.freeKb) * 1024 or nil
	local largest, order = 0, {}
	for index, row in ipairs(rows) do
		row.children = nil
		row.color = hues[row.id]
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

-- What the Overview's "not measured" card explains: how much used space no
-- category holds, and each reason, with the one action that helps where
-- there is one. `options`: fullDiskAccess, diskAccess (false while the App
-- Sandbox hides the startup disk), snapshotCount, mediaExcluded.
function Categories:unmeasured(disk, options)
	options = options or {}
	local items = {}
	local protected = Scans:protected(options.fullDiskAccess)
	if protected.count > 0 then
		-- A few names say what kind of folders these are; macOS Folders lists them all.
		local shown = {}
		for index = 1, math.min(#protected.names, Scans.protectedNames) do table.insert(shown, protected.names[index]) end
		local rest = #protected.names - #shown
		local named = #shown > 0 and ("Including " .. table.concat(shown, ", ") .. ((rest > 0 or protected.refused > 0) and ", and other system folders" or "") .. ". ") or ""
		table.insert(items, {id = "protected", icon = "lock.shield.fill", color = "systemGray", title = "Protected by macOS",
			value = Format.count(protected.count) .. (protected.count == 1 and " location" or " locations"),
			detail = named .. "No app can read these, whatever permission it has, so their size cannot be measured."})
	end
	local privacy = options.fullDiskAccess == false and Scans:unreadable() or {paths = {}, total = 0, more = 0}
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
	for _, segment in ipairs((Categories:distribution(disk))) do
		if segment.id == "unreconciled" and segment.bytes > 0 then residual = segment end
	end
	local summary = residual and (residual.size .. " of used space is in no category. It is made up of what follows, and of file system bookkeeping.")
		or "Everything Diskmap could not measure, and why."
	return {items = items, summary = summary, notAttributed = residual and residual.size or nil}
end

-- The Map shows Diskmap's semantic tree from a focus node downwards: the
-- whole disk, a category, or a group. Rings and rectangles draw the same
-- nodes. Nodes under 1.5% of the map (about 5 degrees of the rings) fold into
-- one "Other" node per parent so every mark is big enough to see and to
-- point at. An outer-ring "Other" that is itself a sliver is left out: its
-- parent's arc simply ends early, which reads as "and a little more". So is
-- one that would be its parent's only child: a grey ring that repeats the
-- parent says nothing, so the parent ends the map there like a leaf.
Categories.mapDepth = 3
Categories.mapMinimumShare = 0.015

local function measured(row)
	return row.bytes ~= nil and row.bytes > 0
end

-- The focused row and its ancestors, root first, for the breadcrumb.
function Categories:path(focus)
	local trail = {}
	local resource = focus and Locations:find(focus)
	while resource do
		table.insert(trail, 1, {id = resource.id, name = resource.name})
		resource = resource:parent()
	end
	table.insert(trail, 1, {id = "", name = "All Storage"})
	return trail
end

-- Nodes {id, parent, value, color, label, detail, ring, hatched, leaf} for
-- the focus. The top level is the focus's children (or the categories).
function Categories:mapNodes(focus, depth)
	depth = depth or Categories.mapDepth
	local top = Categories:rows(focus ~= "" and focus or nil)
	local total = 0
	for _, row in ipairs(top) do if measured(row) then total = total + row.bytes end end
	local nodes = {}
	local hues = Categories:hues(top)
	local function visit(rows, parent, ring, color)
		local other, otherBytes, shown = 0, 0, 0
		for _, row in ipairs(rows) do
			if measured(row) then
				if total > 0 and row.bytes / total < Categories.mapMinimumShare then
					other, otherBytes = other + 1, otherBytes + row.bytes
				else
					shown = shown + 1
					local resource = Locations:find(row.id)
					local leaf = resource and resource:isLeaf()
					local rowColor = ring == 1 and (hues[row.id] or "systemGray") or color
					table.insert(nodes, {id = row.id, parent = parent, value = row.bytes, color = rowColor,
						label = row.name, detail = row.size, ring = ring, leaf = leaf,
						hatched = leaf and resource.policy == "Rebuildable" or false})
					if row.children and ring < depth then visit(row.children, row.id, ring + 1, rowColor) end
				end
			end
		end
		if other > 0 and (ring == 1 or (shown > 0 and otherBytes / total >= Categories.mapMinimumShare)) then
			-- Nested smaller items are more of their parent, so they keep its
			-- hue (the view fades them); only the top level has no family.
			table.insert(nodes, {id = (parent or "top") .. "#other", parent = parent, value = otherBytes, color = color or "systemGray",
				label = other .. " smaller", detail = Format.size(otherBytes), ring = ring, leaf = true, other = true})
		end
	end
	visit(top, nil, 1, nil)
	return nodes, total
end

-- Largest rebuildable resources under the focus: the "Worth a look" list.
function Categories:worthALook(focus, limit)
	local model = Model.db
	local rows = {}
	local root = focus ~= "" and focus and Locations:find(focus)
	local function within(resource)
		if not root then return true end
		while resource do
			if resource == root then return true end
			resource = resource:parent()
		end
		return false
	end
	for _, resource in ipairs(Locations:leaves()) do
		local m = model.measurements[resource.id]
		if resource.policy == "Rebuildable" and m and m.status == "complete" and (m.bytes or 0) > 0
			and within(resource) and not resource:isKept() then
			table.insert(rows, {id = resource.id, name = resource.name, path = resource.path, bytes = m.bytes,
				size = Format.size(m.bytes), action = resource.action})
		end
	end
	table.sort(rows, function(a, b) return a.bytes > b.bytes end)
	while #rows > (limit or 3) do table.remove(rows) end
	return rows
end

-- One line describing a node for the hover bar.
function Categories:describe(id, total)
	local row = id and Categories:row(id)
	if not row then return nil end
	local share = total and total > 0 and row.bytes and string.format(" · %.1f%%", row.bytes * 100 / total) or ""
	local trail = {}
	for _, step in ipairs(Categories:path(id)) do if step.id ~= "" then table.insert(trail, step.name) end end
	return table.concat(trail, " › ") .. " · " .. row.size .. share
end

function Categories:snapshot(time)
	local totals = {}
	for _, row in ipairs(Categories:rows()) do
		if row.status == "complete" and row.bytes then totals[row.id] = row.bytes end
	end
	return {time = time or os.time(), totals = totals}
end

-- The largest changes between the oldest entry within `days` and the newest
-- one, as rows for the overview. Categories missing from either end are
-- skipped rather than reported as appearing or vanishing.
function Categories:changes(entries, days, limit, now)
	if not entries or #entries < 2 then return nil end
	local latest = entries[#entries]
	local since = (now or latest.time) - (days or 30) * 86400
	local base
	for _, entry in ipairs(entries) do
		if entry ~= latest and entry.time >= since then base = entry; break end
	end
	base = base or entries[#entries - 1]
	local rows = {}
	for id, bytes in pairs(latest.totals) do
		local before = base.totals[id]
		local resource = Locations:find(id)
		if before and resource and bytes ~= before then
			local delta = bytes - before
			table.insert(rows, {id = id, name = resource.name, color = resource.color, icon = resource.icon, delta = delta,
				text = (delta > 0 and "+" or "−") .. Format.size(math.abs(delta)), grew = delta > 0})
		end
	end
	table.sort(rows, function(a, b)
		if math.abs(a.delta) ~= math.abs(b.delta) then return math.abs(a.delta) > math.abs(b.delta) end
		return a.id < b.id
	end)
	while #rows > (limit or 4) do table.remove(rows) end
	if #rows == 0 then return nil end
	local since = (os.date("%b %e", base.time):gsub("  ", " "))
	return {rows = rows, since = since, scans = #entries, detail = "Since " .. since .. " · " .. #entries .. " scans recorded"}
end


return Categories
