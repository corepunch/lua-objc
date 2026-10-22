-- The Plugins sheet: every provider the extension point loaded, where it
-- came from, and the plugin files that failed to load.
local Plugins = {}

Plugins.folder = "Plugins"

function Plugins.presentation(point, problems, hasKey)
	local rows = {}
	for _, descriptor in ipairs(point:list()) do
		local models = {}
		for _, model in ipairs(descriptor.models) do table.insert(models, model.title) end
		table.insert(rows, {
			id = descriptor.id,
			title = descriptor.title,
			symbol = descriptor.symbol or "cpu",
			origin = descriptor.source == "user" and descriptor.file or "Bundled with Studio",
			models = table.concat(models, ", "),
			keyStatus = hasKey and hasKey(descriptor.id) and "Key saved" or "No key",
		})
	end
	local failures = {}
	for _, problem in ipairs(problems or {}) do
		table.insert(failures, { file = problem.file, message = problem.message })
	end
	return { plugins = rows, problems = failures, folder = Plugins.folder }
end

return Plugins
