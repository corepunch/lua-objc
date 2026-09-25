-- Compose domain providers; IDs and exact paths form the ownership ledger.
local Catalog = {}
local Apple = require("apps.diskmap.catalog.AppleSections")
local providers = {
	(require("apps.diskmap.catalog.Applications")),
	(require("apps.diskmap.catalog.Trash")),
	Apple.books,
	(require("apps.diskmap.catalog.Developer")),
	(require("apps.diskmap.catalog.Documents")),
	Apple.icloud,
	Apple.iosFiles,
	Apple.mail,
	Apple.messages,
	Apple.music,
	Apple.musicCreation,
	(require("apps.diskmap.catalog.Photos")),
	Apple.podcasts,
	Apple.tv,
	(require("apps.diskmap.catalog.AIAgents")),
	Apple.otherUsers,
	(require("apps.diskmap.catalog.Backups")),
	(require("apps.diskmap.catalog.MacOS")),
	(require("apps.diskmap.catalog.SystemData")),
	(require("apps.diskmap.catalog.Other")),
}
function Catalog.tree(home)
	local tree = {}
	for _, provider in ipairs(providers) do table.insert(tree, (provider())) end
	local owners = {
		xcode = "com.apple.dt.Xcode", ["vscode-data"] = "com.microsoft.VSCode",
		["vscode-extensions"] = "com.microsoft.VSCode", cursor = "com.todesktop.230313mzl4w4u92",
		docker = "com.docker.docker", mail = "com.apple.mail", ["mail-library"] = "com.apple.mail",
		messages = "com.apple.MobileSMS", ["messages-library"] = "com.apple.MobileSMS",
		books = "com.apple.iBooksX", ["music-library"] = "com.apple.Music",
		photos = "com.apple.Photos", podcasts = "com.apple.podcasts", tv = "com.apple.TV",
	}
	local function resolve(rows)
		for _, row in ipairs(rows) do
			row.appIcon = owners[row.id]
			if row.path then row.path = row.path:gsub("^~", function() return home end) end
			if row.children then resolve(row.children) end
		end
	end
	resolve(tree)
	return tree
end
-- Discovery rules are intentionally separate from fixed catalog paths. They
-- add individually measured generated folders after their project marker is
-- observed and app bundles by name, while parent roots remain residual owners.
function Catalog.discoveryRules(home)
	local generated = require("apps.diskmap.catalog.Definitions").generated
	return {
		{root = home .. "/Developer", parentId = "developer", rules = {
			generated("package.json", "node_modules", {name = "Node modules", subtitle = "Installed JavaScript dependencies for a project; review before removing"}),
			generated("Cargo.toml", "target", {name = "Rust build output", subtitle = "Generated Cargo artifacts for a project; review before removing"}),
			generated("CMakeCache.txt", "build", {name = "CMake build output", subtitle = "Generated build files for a project; review before removing"}),
			generated("pyproject.toml", ".venv", {name = "Python virtual environment", subtitle = "Installed project environment; review packages before removing"}),
		}},
		{root = "/Applications", parentId = "apps-system", applications = true},
		{root = home .. "/Applications", parentId = "apps-user", applications = true},
	}
end
return Catalog
