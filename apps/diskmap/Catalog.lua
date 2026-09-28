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
-- Marker file beside the folder, then the folder a build or install creates.
-- A folder name shared by several ecosystems ("build", "target") belongs to
-- the first rule whose marker is present. `plain` explains the ecosystem's
-- total to someone who never ran the tool; `rebuildable` rules become
-- Rebuildable when an `inner` file proves the tool wrote the folder
-- (CACHEDIR.TAG in a Cargo target, pyvenv.cfg in a virtual environment).
local PYTHON = {"pyproject.toml", "requirements.txt", "setup.py", "Pipfile", "uv.lock"}
local NEXT = {"next.config.js", "next.config.mjs", "next.config.ts", "package.json"}
function Catalog.buildRules()
	local generated = require("apps.diskmap.catalog.Definitions").generated
	local venv = {name = "Python virtual environments", subtitle = "Installed Python packages for a project; review before removing",
		plain = "Python packages installed for projects. Reinstalling the project's requirements downloads them again.", inner = {"pyvenv.cfg"}}
	return {
		generated("package.json", "node_modules", {name = "Node modules", subtitle = "Installed JavaScript dependencies; npm, pnpm or yarn install restores them",
			plain = "Downloaded code libraries. Running the project's install command downloads them again.",
			inner = {".package-lock.json", ".modules.yaml", ".yarn-state.yml", ".yarn-integrity"}, rebuildable = true,
			consequence = "Running the project's install command (npm, pnpm or yarn install) downloads these libraries again. Moving to Trash does not free space until you empty it."}),
		generated("Cargo.toml", "target", {name = "Rust build output", subtitle = "Generated Cargo artifacts; cargo build recreates them",
			plain = "Files a Rust build produced. The next build makes them again, more slowly.",
			inner = {"CACHEDIR.TAG", ".rustc_info.json"}, rebuildable = true,
			consequence = "cargo build recreates this folder; the next build takes longer. Moving to Trash does not free space until you empty it."}),
		generated("pom.xml", "target", {name = "Maven build output", subtitle = "Generated Maven artifacts; mvn package recreates them",
			plain = "Files a Java build produced. The next build makes them again."}),
		generated("CMakeCache.txt", "build", {name = "CMake build output", subtitle = "Generated build files; the next configure and build recreate them",
			plain = "Files a C or C++ build produced. The next build makes them again."}),
		generated({"build.gradle", "build.gradle.kts"}, "build", {name = "Gradle build output", subtitle = "Generated Gradle artifacts; the next build recreates them",
			plain = "Files an Android or Java build produced. The next build makes them again."}),
		generated("Package.swift", ".build", {name = "Swift build output", subtitle = "SwiftPM build products and checkouts; swift build recreates them",
			plain = "Files a Swift package build produced. The next build makes them again.",
			inner = {"workspace-state.json"}, rebuildable = true,
			consequence = "swift build recreates this folder and checks out dependencies again. Moving to Trash does not free space until you empty it."}),
		generated("Podfile", "Pods", {name = "CocoaPods dependencies", subtitle = "Installed CocoaPods libraries; pod install restores them",
			plain = "Downloaded libraries for iPhone and Mac projects. Running pod install downloads them again.",
			inner = {"Manifest.lock"}, rebuildable = true,
			consequence = "pod install downloads these libraries again. Moving to Trash does not free space until you empty it."}),
		generated(PYTHON, ".venv", venv),
		generated(PYTHON, "venv", venv),
		generated("pubspec.yaml", ".dart_tool", {name = "Dart tool cache", subtitle = "Generated Dart and Flutter tooling data; pub get recreates it",
			plain = "Files Flutter and Dart tools generated. They come back on the next build."}),
		generated(NEXT, ".next", {name = "Next.js build output", subtitle = "Generated Next.js build; the next build recreates it",
			plain = "A website build. Building the site again makes it again.",
			inner = {"BUILD_ID", "build-manifest.json", "trace"}, rebuildable = true,
			consequence = "The next Next.js build recreates this folder. Moving to Trash does not free space until you empty it."}),
		generated("turbo.json", ".turbo", {name = "Turborepo cache", subtitle = "Local task cache; the next run recreates it",
			plain = "A cache of build results. The next build makes it again."}),
		generated("project.godot", ".godot", {name = "Godot import cache", subtitle = "Imported assets; Godot reimports on open",
			plain = "Game assets Godot imported. Godot imports them again when the project opens."}),
		generated("build.zig", ".zig-cache", {name = "Zig build cache", subtitle = "Generated Zig artifacts; zig build recreates them",
			plain = "Files a Zig build produced. The next build makes them again."}),
		generated("mix.exs", "_build", {name = "Elixir build output", subtitle = "Compiled Elixir artifacts; mix compile recreates them",
			plain = "Files an Elixir build produced. The next build makes them again."}),
		generated("stack.yaml", ".stack-work", {name = "Haskell Stack build output", subtitle = "Generated Stack artifacts; stack build recreates them",
			plain = "Files a Haskell build produced. The next build makes them again."}),
		generated("ProjectSettings/ProjectVersion.txt", "Library", {name = "Unity library cache", subtitle = "Imported Unity assets; Unity reimports on open, which can take a while",
			plain = "Game assets Unity imported. Unity imports them again when the project opens, which can take a while."}),
	}
end

-- The ecosystem group for a rule name ("Node modules"): one synthetic group
-- per artifact under Developer, whose children are the per-project folders.
-- The Projects page groups the same leaves by project instead.
function Catalog.buildGroup(artifact)
	for _, rule in ipairs(Catalog.buildRules()) do
		if rule.name == artifact then
			return {id = "build-" .. rule.name:lower():gsub("[^%w]+", "-"):gsub("%-$", ""), name = rule.name,
				subtitle = rule.plain or rule.subtitle, icon = "shippingbox.fill", color = "systemOrange", children = {}}
		end
	end
end

-- Where people keep projects (Headroom's list): folders under the home
-- folder, deduplicated case-insensitively as APFS resolves them. Documents,
-- Desktop and iCloud Drive are protected by macOS; searching them without
-- Full Disk Access would ask the person once per folder, so they are
-- searched only when access is already granted.
Catalog.projectFolders = {"Developer", "code", "Code", "Projects", "projects", "src", "dev", "repos", "GitHub", "Sites"}
Catalog.protectedProjectFolders = {"Documents", "Desktop", "Library/Mobile Documents/com~apple~CloudDocs"}
-- Never descended while searching: version control, the Trash, app bundles,
-- libraries and other packages, which hold no project build folders.
Catalog.discoverySkip = {".git", ".Trash", "*.app", "*.photoslibrary", "*.xcarchive", "*.fcpbundle", "*.logicx",
	"*.musiclibrary", "*.tvlibrary", "*.imovielibrary", "*.sparsebundle", "*.xcodeproj", "*.xcworkspace"}
Catalog.discoveryDepth = 6

function Catalog.projectRoots(home, projectRoots, fullDiskAccess)
	local roots, seen = {}, {}
	local function add(path)
		local key = path:gsub("/+$", ""):lower()
		if not seen[key] then seen[key] = true; table.insert(roots, path) end
	end
	for _, name in ipairs(Catalog.projectFolders) do add(home .. "/" .. name) end
	if fullDiskAccess then
		for _, name in ipairs(Catalog.protectedProjectFolders) do add(home .. "/" .. name) end
	end
	for _, root in ipairs(projectRoots or {}) do add(root) end
	return roots
end

-- The `find` arguments for build folders under `roots`: skipped folders are
-- pruned, the depth is capped and a matched folder is never descended into.
function Catalog.findArguments(roots, rules)
	local argv = {"/usr/bin/find"}
	for _, root in ipairs(roots) do table.insert(argv, root) end
	for _, value in ipairs({"-maxdepth", tostring(Catalog.discoveryDepth), "("}) do table.insert(argv, value) end
	for index, name in ipairs(Catalog.discoverySkip) do
		if index > 1 then table.insert(argv, "-o") end
		table.insert(argv, "-name"); table.insert(argv, name)
	end
	for _, value in ipairs({")", "-prune", "-o", "-type", "d", "("}) do table.insert(argv, value) end
	local names = {}
	for _, rule in ipairs(rules) do
		if not names[rule.dirName] then
			if next(names) then table.insert(argv, "-o") end
			names[rule.dirName] = true
			table.insert(argv, "-name"); table.insert(argv, rule.dirName)
		end
	end
	for _, value in ipairs({")", "-prune", "-print"}) do table.insert(argv, value) end
	return argv
end

function Catalog.discoveryRules(home, projectRoots, fullDiskAccess)
	return {
		{roots = Catalog.projectRoots(home, projectRoots, fullDiskAccess), parentId = "developer", rules = Catalog.buildRules()},
		{root = "/Applications", parentId = "apps-system", applications = true},
		{root = home .. "/Applications", parentId = "apps-user", applications = true},
	}
end
return Catalog
