-- The Status column shows each row's cleanup status as one colour-coded
-- symbol: green when its owner rebuilds it or it is within limits, orange
-- when it needs review, red when it must stay. The status word stays in
-- `detail` for the tooltip and VoiceOver; distinct symbols keep the
-- statuses apart without relying on colour alone.
local Status = {}

local STYLES = {
	Rebuildable = {icon = "arrow.triangle.2.circlepath.circle.fill", color = "systemGreen"},
	Review = {icon = "eye.circle.fill", color = "systemOrange"},
	Keep = {icon = "lock.circle.fill", color = "systemRed"},
	Essential = {icon = "lock.circle.fill", color = "systemRed"},
	["System managed"] = {icon = "gearshape.circle.fill", color = "systemGray"},
	Kept = {icon = "pin.circle.fill", color = "systemBlue"},
	Within = {icon = "checkmark.circle.fill", color = "systemGreen"},
	Page = {icon = "arrow.forward.circle.fill", color = "systemGray"},
}
Status.styles = STYLES

-- Sets `statusIcon` and `statusColor` from `detail`, or from `kind` when the
-- detail is descriptive text such as "Under 5.0 GB". Rows without a status
-- (a rolled-up group) keep an empty cell.
function Status.apply(row, kind)
	local style = STYLES[kind or row.detail]
	row.statusIcon = style and style.icon or ""
	row.statusColor = style and style.color or nil
	return row
end

function Status.applyAll(rows, kind)
	for _, row in ipairs(rows) do Status.apply(row, kind) end
	return rows
end

return Status
