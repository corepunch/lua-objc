local Format = require("apps.diskmap.helpers.Format")
local Overview = {}

-- The part of used capacity that no file scan can attribute, split into what
-- macOS reports separately: purgeable storage, local snapshots and locations
-- Diskmap could not read. Sizes appear only where macOS provides them.
-- `mediaExcluded` names the Photos, Music and TV libraries while they are
-- left out of the scan, so a disk that is full of photos says where they are.
-- `readErrors` counts every refused location; `protected` (from
-- Scans:protected) the ones macOS keeps from every app, which no
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

-- What the ring's hole says while no sector is pointed at: the used space
-- and the disk's capacity.
function Overview.center(summary)
	return {title = summary.used, detail = summary.available and (summary.total .. " total") or "Capacity unavailable"}
end

-- The Overview's breakdown card (views/sections/Breakdown.etlua): the volume,
-- its capacity line, a low-space warning and the categories of `chart`.
function Overview.breakdown(summary, chart, volumeName, style)
	return {style = style, title = volumeName, detail = summary.subtitle or summary.caption,
		warning = summary.lowSpace and summary.lowSpaceMessage or "", explanation = chart.explanation, center = Overview.center(summary),
		marks = chart.marks, legend = chart.legend, accessibilityLabel = chart.accessibilityLabel}
end

return Overview
