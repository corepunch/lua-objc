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
function Catalog.discoveryRules(home, projectRoots)
	local generated = require("apps.diskmap.catalog.Definitions").generated
	-- Marker file beside the folder, then the folder a build or install creates.
	-- A folder name shared by several ecosystems ("build", "target") belongs to
	-- the first rule whose marker is present.
	local rules = {
		generated("package.json", "node_modules", {name = "Node modules", subtitle = "Installed JavaScript dependencies; npm, pnpm or yarn install restores them"}),
		generated("Cargo.toml", "target", {name = "Rust build output", subtitle = "Generated Cargo artifacts; cargo build recreates them"}),
		generated("pom.xml", "target", {name = "Maven build output", subtitle = "Generated Maven artifacts; mvn package recreates them"}),
		generated("CMakeCache.txt", "build", {name = "CMake build output", subtitle = "Generated build files; the next configure and build recreate them"}),
		generated("build.gradle", "build", {name = "Gradle build output", subtitle = "Generated Gradle artifacts; the next build recreates them"}),
		generated("build.gradle.kts", "build", {name = "Gradle build output", subtitle = "Generated Gradle artifacts; the next build recreates them"}),
		generated("Package.swift", ".build", {name = "Swift build output", subtitle = "SwiftPM build products and checkouts; swift build recreates them"}),
		generated("pyproject.toml", ".venv", {name = "Python virtual environment", subtitle = "Installed project environment; review packages before removing"}),
		generated("pubspec.yaml", ".dart_tool", {name = "Dart tool cache", subtitle = "Generated Dart and Flutter tooling data; pub get recreates it"}),
		generated("next.config.js", ".next", {name = "Next.js build output", subtitle = "Generated Next.js build; the next build recreates it"}),
		generated("next.config.mjs", ".next", {name = "Next.js build output", subtitle = "Generated Next.js build; the next build recreates it"}),
		generated("turbo.json", ".turbo", {name = "Turborepo cache", subtitle = "Local task cache; the next run recreates it"}),
		generated("project.godot", ".godot", {name = "Godot import cache", subtitle = "Imported assets; Godot reimports on open"}),
		generated("build.zig", ".zig-cache", {name = "Zig build cache", subtitle = "Generated Zig artifacts; zig build recreates them"}),
		generated("mix.exs", "_build", {name = "Elixir build output", subtitle = "Compiled Elixir artifacts; mix compile recreates them"}),
		generated("stack.yaml", ".stack-work", {name = "Haskell Stack build output", subtitle = "Generated Stack artifacts; stack build recreates them"}),
		generated("ProjectSettings/ProjectVersion.txt", "Library", {name = "Unity library cache", subtitle = "Imported Unity assets; Unity reimports on open, which can take a while"}),
	}
	local locations = {}
	local seen = {}
	for _, root in ipairs({home .. "/Developer", table.unpack(projectRoots or {})}) do
		if not seen[root] then
			seen[root] = true
			table.insert(locations, {root = root, parentId = "developer", rules = rules})
		end
	end
	table.insert(locations, {root = "/Applications", parentId = "apps-system", applications = true})
	table.insert(locations, {root = home .. "/Applications", parentId = "apps-user", applications = true})
	return locations
end
return Catalog
