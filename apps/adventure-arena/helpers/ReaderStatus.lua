local Plurals = require("apps.adventure-arena.helpers.Plurals")

-- The reader's own lines that are made of numbers: the running head's second
-- line and the score toast. Pure; `strings` are the app's resources in the
-- language being read (resources.xml: moveCount_*, scoreOf, pointCount_* ...).
local ReaderStatus = {}

-- The running head's second line: moves for a story that counts them,
-- otherwise the score.
function ReaderStatus.progress(strings, statusLine, score, maxScore, moves)
	if statusLine == "moves" then
		return Plurals.format(strings, "moveCount", moves or 0)
	end
	return maxScore > 0 and string.format(strings.scoreOf, score, maxScore) or string.format(strings.scoreOnly, score)
end

-- Systems opt into automatic monitoring by exporting a bounded resource.
-- The first such row is the system's primary gauge; unbounded values remain
-- on the full sheet. There is no special case for a particular title or RPG.
function ReaderStatus.monitor(sheet)
	for _, row in ipairs(sheet and sheet.rows or {}) do
		local maximum = tonumber(row.maximum)
		if row.group == "resources" and maximum and maximum > 0 then
			return string.format("%s %s/%s", row.label, row.value, row.maximum)
		end
	end
end

function ReaderStatus.toast(strings, change)
	return (change > 0 and "+" or "−") .. Plurals.format(strings, "pointCount", math.abs(change))
end

return ReaderStatus
