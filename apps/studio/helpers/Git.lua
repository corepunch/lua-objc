local Git = {}

-- The message a commit gets when the field is left empty.
Git.defaultMessage = "Update project"

-- History rows for the Source Control list, newest first, from the log
-- entries the repository returns ({shortId, summary, author, time}).
-- `now` is passed in so the rows are a pure function of their arguments.
function Git.history(log, now)
	local rows = {}
	for index, entry in ipairs(log or {}) do
		local age = math.max(0, (now or entry.time) - entry.time)
		local when = age < 60 and "just now"
			or age < 3600 and string.format("%d min ago", age // 60)
			or age < 86400 and string.format("%d h ago", age // 3600)
			or os.date("%b %d", entry.time)
		table.insert(rows, {
			id = entry.id,
			summary = entry.summary,
			detail = entry.shortId .. " · " .. when,
			icon = index == 1 and "smallcircle.filled.circle.fill" or "smallcircle.filled.circle",
		})
	end
	return rows
end

function Git.presentation(state)
	return {
		message = state.message or "",
		placeholder = Git.defaultMessage,
		status = state.status or "",
		busy = state.busy == true,
	}
end

return Git
