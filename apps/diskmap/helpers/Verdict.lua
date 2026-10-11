local Format = require("apps.diskmap.helpers.Format")
-- What a row's verdict says and how it looks: one symbol and colour per
-- verdict, the word as its tooltip. Verdicts are facts Diskmap computed or
-- the knowledge table states (knowledge/Locations.lua):
--   safe    rebuilt or downloaded again when needed; Diskmap can remove it
--   review  yours to decide; Diskmap can remove it after you flag it
--   owner   cleared in the owning app or its command; Diskmap opens the owner
--   system  macOS manages it; Diskmap explains it and does nothing
--   keep    needed now (the newest device support, a running simulator), or marked Keep
local Verdict = {}

Verdict.styles = {
	safe = {label = "Safe to remove", icon = "checkmark.circle.fill", color = "systemGreen"},
	review = {label = "Your decision", icon = "questionmark.circle.fill", color = "systemOrange"},
	owner = {label = "In its app", icon = "arrow.up.forward.app.fill", color = "systemTeal"},
	system = {label = "Managed by macOS", icon = "gearshape.circle.fill", color = "systemGray"},
	keep = {label = "Keep", icon = "lock.circle.fill", color = "systemRed"},
}
Verdict.order = {safe = 1, review = 2, owner = 3, keep = 4, system = 5}

-- Which verdicts Diskmap may act on after a flag, and with which action.
function Verdict.removable(verdict) return verdict == "safe" or verdict == "review" end

-- The size column: the size, or the state that stands in for it.
local STATES = {missing = "Not present", denied = "No access", failed = "Unavailable", pending = "Measuring…"}
function Verdict.sizeText(row)
	if row.state ~= "measured" and STATES[row.state] then return STATES[row.state] end
	return Format.atLeast(row.bytes, row.partial)
end

-- Fills the presentation of a row from its verdict and state: the symbol,
-- its colour, the status word, the size text and the second line.
function Verdict.present(row, now)
	local style = Verdict.styles[row.verdict] or Verdict.styles.review
	row.statusIcon, row.statusColor, row.status = style.icon, style.color, style.label
	if row.state == "pending" then row.statusIcon, row.statusColor, row.status = "", nil, "" end
	local parts = {}
	if row.owner then table.insert(parts, row.owner) end
	if row.used and row.used > 0 then table.insert(parts, "written " .. Format.age(row.used, now):lower()) end
	if row.state == "denied" then table.insert(parts, "Diskmap cannot read it") end
	if row.partial then table.insert(parts, "some of it could not be read") end
	if row.admin then table.insert(parts, "needs an administrator") end
	row.subtitle = table.concat(parts, " · ")
	row.size = Verdict.sizeText(row)
	row.help = row.reason or row.what
	return row
end

return Verdict
