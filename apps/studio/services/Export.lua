local Export = {}
local Workspaces = require("apps.studio.Model")

-- Only manifest-owned source and project artwork are shared. Runtime data,
-- Git internals, Studio preferences and the Keychain stay on the device.
function Export.items(project, files)
	assert(type(project) == "string" and project:match("^[%w_%-]+$"), "Invalid project name")
	local result = {}
	for path, source in pairs(files) do
		assert(Workspaces.validPath(path), "Invalid project source")
		local relative = path:match("^demo/playground/(.+)$")
		assert(relative, "Invalid project source")
		-- Standalone bundles resolve modules at their real apps/<project> path.
		local exported = source:gsub("demo%.playground", "apps." .. project):gsub("demo/playground", "apps/" .. project)
		table.insert(result, { text = exported, name = relative })
	end
	table.insert(result, { name = "README.md", text = "# " .. project .. "\n\n"
		.. "Copy this folder to apps/" .. project .. " in a lua-objc checkout.\n"
		.. "Run make ios-run PROJECT=apps/" .. project .. " for the iPhone host, or\n"
		.. "make iphone-deploy APP=" .. project .. " for a paired iPhone with development signing.\n"
		.. "App Store distribution requires a separate release/signing configuration.\n\n"
		.. "Export rewrites Studio's demo.playground namespace to apps." .. project .. ".\n"
		.. "The original iPad project is unchanged. Runtime data, Git and keys are excluded.\n" })
	for _, name in ipairs({ "project.lua", "AppIcon.png" }) do
		table.insert(result, { source = project .. "/" .. name, name = name })
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end

function Export.share(ns, project, files)
	return ns.shareFiles(Export.items(project.id, files), project.id)
end
return Export
