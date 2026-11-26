-- What the reader's own controls say, by the story's language (its
-- catalog `language`, carried by the session presentation). English is the
-- default; the engine's reader speaks for menus and completions.
local ReaderText = {}

local STRINGS = {
	en = {
		placeholder = "What do you do?", command = "Command", send = "Send command", dictate = "Dictate command",
		score = "Score", points = "Points", point = "point", pointsUnit = "points",
		scoreOf = "Score %d of %d", scoreOnly = "Score %d", oneMove = "1 move", moves = "%d moves",
	},
	de = {
		placeholder = "Was tust du?", command = "Befehl", send = "Befehl senden", dictate = "Befehl diktieren",
		score = "Punkte", points = "Punkte", point = "Punkt", pointsUnit = "Punkte",
		scoreOf = "Punkte %d von %d", scoreOnly = "Punkte %d", oneMove = "1 Zug", moves = "%d Züge",
	},
}

function ReaderText.strings(language)
	return STRINGS[language] or STRINGS.en
end

-- The running head's second line: moves for a story that counts them,
-- otherwise the score.
function ReaderText.progress(text, statusLine, score, maxScore, moves)
	if statusLine == "moves" then
		return moves == 1 and text.oneMove or string.format(text.moves, moves or 0)
	end
	return maxScore > 0 and string.format(text.scoreOf, score, maxScore) or string.format(text.scoreOnly, score)
end

function ReaderText.toast(text, change)
	local unit = math.abs(change) == 1 and text.point or text.pointsUnit
	return string.format("%s%d %s", change > 0 and "+" or "−", math.abs(change), unit)
end

return ReaderText
