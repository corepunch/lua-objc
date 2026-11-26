-- The reader's own lines that are made of numbers: the running head's second
-- line and the score toast. Pure; `strings` are the app's resources in the
-- language being read (resources.xml: moves, scoreOf, point ...).
local ReaderStatus = {}

-- The running head's second line: moves for a story that counts them,
-- otherwise the score.
function ReaderStatus.progress(strings, statusLine, score, maxScore, moves)
	if statusLine == "moves" then
		return moves == 1 and strings.oneMove or string.format(strings.moves, moves or 0)
	end
	return maxScore > 0 and string.format(strings.scoreOf, score, maxScore) or string.format(strings.scoreOnly, score)
end

function ReaderStatus.toast(strings, change)
	local unit = math.abs(change) == 1 and strings.point or strings.pointsUnit
	return string.format("%s%d %s", change > 0 and "+" or "−", math.abs(change), unit)
end

return ReaderStatus
