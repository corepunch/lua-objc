local Model = require("data.model")
local Categories = require("apps.diskmap.models.Categories")
local Items = require("apps.diskmap.models.Items")
local Format = require("apps.diskmap.helpers.Format")

-- The front page: the disk as one bar with a segment per source, the
-- number that can go now, and the sources ranked by what they hold. Every
-- number here is a sum over the rows the category pages list; nothing is
-- measured for this page alone.
local routes = {}
local Overview = {view = "pages/Overview", queries = {}}
routes.overview = Overview

function Overview:init() self.rows = self:flow("Rows") end

-- The bar: measured sources, what else is used, and free space.
function Overview:segments(state)
	local segments, measured = {}, 0
	for _, category in ipairs(Categories:ranked()) do
		local bytes = category:bytes()
		if bytes > 0 then
			measured = measured + bytes
			table.insert(segments, {value = bytes, color = category.color, label = category.title .. " " .. Format.size(bytes)})
		end
	end
	local capacity = state.capacity
	local used = capacity and capacity.total and capacity.available and (capacity.total - capacity.available) or nil
	-- Volumes are measured by their own size and are not part of "used"
	-- as the Data volume reports it; the bar is capped at the disk.
	if used and used > measured then table.insert(segments, {value = used - measured, color = "tertiaryLabel", label = "Everything else " .. Format.size(used - measured)}) end
	return segments, capacity and capacity.total or math.max(measured, used or 0), used
end

function Overview:data(state)
	local segments, total, used = self:segments(state)
	local safe, review, denied = 0, 0, 0
	for _, row in ipairs(Items:all()) do
		if row.verdict == "safe" then safe = safe + (row.bytes or 0)
		elseif row.verdict == "review" then review = review + (row.bytes or 0) end
		if row.state == "denied" then denied = denied + 1 end
	end
	local categories = {}
	for _, category in ipairs(Categories:ranked()) do
		local bytes, safeBytes = category:totals()
		local count = #category:items()
		local pending = Model.db.scan.pending[category.id] == true
		table.insert(categories, {id = category.id, name = category.title, icon = category.icon, color = category.color,
			subtitle = category.summary, shareText = total > 0 and bytes > 0 and Format.percent(bytes, total) or "", size = pending and "Measuring…" or (count == 0 and "Nothing found" or Format.size(bytes)),
			safe = safeBytes > 0 and (Format.size(safeBytes) .. " safe") or "", calculating = pending,
			relative = total > 0 and bytes / total or 0, bytes = bytes})
	end
	local measuring = Model.db.scan.running
	local headline
	if measuring and safe == 0 then headline = "Measuring the places developers lose space to…"
	elseif safe > 0 then headline = Format.size(safe) .. " can go now"
	else headline = "Nothing safe to remove was found" end
	local detail = {}
	if safe > 0 then table.insert(detail, "Caches, build output and device data that tools make again when needed.") end
	if review > 0 then table.insert(detail, Format.size(review) .. " more is yours to decide: history, downloads and work in progress.") end
	local free = state.disk and state.disk.freeKb and state.disk.freeKb * 1024
	local subtitle = free and used and (Format.size(free) .. " free of " .. Format.size(total) .. " · " .. Format.size(used) .. " used") or ""
	return {
		title = "Overview", subtitle = subtitle,
		headline = headline, detail = table.concat(detail, " "),
		segments = segments, total = total, accessibility = subtitle,
		lists = {categories = categories},
		notice = Model.db.notice or "",
		hidden = {removeSafe = safe == 0 or measuring, access = denied == 0, detail = detail[1] == nil, notice = Model.db.notice == nil},
		disabled = {removeSafe = safe == 0},
		accessNote = denied > 0 and (Format.plural(denied, "location") .. " could not be read. Full Disk Access lets Diskmap measure them.") or "",
	}
end

function Overview:open(_, _, row) if row then self.app.show(row.id) end end

-- Removes every safe row of every source, after one confirmation.
function Overview:removeSafe() return self.rows:removeSafe(Items:all()) end
function Overview:access() self.app.service.openSettings("privacy") end

return routes
