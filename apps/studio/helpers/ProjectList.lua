local ProjectList = {}

-- Rows for the Projects list: every project on this iPad, the open one
-- marked as current, the others with their bundle identifier.
function ProjectList.rows(projects)
	local rows = {}
	for _, project in ipairs(projects or {}) do
		table.insert(rows, {
			id = project.id,
			title = project.title,
			icon = project.icon or "app",
			detail = project.selected and "Current project" or (project.bundleId or ""),
		})
	end
	return rows
end

function ProjectList.presentation(projects, iconChoices)
	local current
	for _, project in ipairs(projects or {}) do if project.selected then current = project end end
	return { current = current, iconChoices = iconChoices or {} }
end

return ProjectList
