-- Build output beside the project that makes it: the folder name, the file
-- next to it that proves there is a project (`markers`), and the file inside
-- it that proves the folder is the build system's own output (`inner`). With
-- both proofs the folder is rebuilt by the next build; with the marker alone
-- it is still the person's to review (a `build` folder beside a Makefile may
-- hold anything). `name` is the row's name, `owner` the tool.
local Builds = {}

Builds.rules = {
	{dirName = "node_modules", markers = {"package.json"}, inner = {".package-lock.json", ".yarn-integrity", ".modules.yaml"}, name = "Node modules", owner = "npm",
		what = "Installed JavaScript packages. npm install, pnpm install or yarn restores them from the lockfile."},
	{dirName = "target", markers = {"Cargo.toml"}, inner = {"CACHEDIR.TAG"}, name = "Cargo build", owner = "Cargo",
		what = "Compiled crates and binaries. cargo build makes them again."},
	{dirName = "target", markers = {"pom.xml"}, inner = {"classes", "maven-status"}, name = "Maven build", owner = "Maven",
		what = "Compiled classes and packaged artifacts. mvn package makes them again."},
	{dirName = "build", markers = {"build.gradle", "build.gradle.kts"}, inner = {"tmp", "intermediates", "generated"}, name = "Gradle build", owner = "Gradle",
		what = "Compiled classes and generated sources. gradle build makes them again."},
	{dirName = "build", markers = {"CMakeLists.txt"}, inner = {"CMakeCache.txt"}, name = "CMake build", owner = "CMake",
		what = "Configured build tree and compiled objects. cmake and a build make them again."},
	{dirName = "build", markers = {"Makefile", "meson.build", "premake5.lua", "BUILD", "BUILD.bazel"}, inner = {}, name = "Build folder", owner = "Build system",
		what = "Output of this project's build. Whether the next build recreates everything in it depends on the build system."},
	{dirName = "Build", markers = {"*.xcodeproj", "*.xcworkspace", "Makefile"}, inner = {"Intermediates.noindex", "Products"}, name = "Xcode build", owner = "Xcode",
		what = "Xcode's build products and intermediates kept inside the project. The next build makes them again."},
	{dirName = "DerivedData", markers = {"*.xcodeproj", "*.xcworkspace", "Package.swift"}, inner = {"ModuleCache.noindex", "Build", "Index.noindex"}, name = "Project DerivedData", owner = "Xcode",
		what = "Build products and indexes Xcode keeps inside the project. The next build makes them again."},
	{dirName = ".build", markers = {"Package.swift"}, inner = {"workspace-state.json"}, name = "Swift build", owner = "Swift Package Manager",
		what = "Compiled Swift packages and resolved dependencies. swift build makes them again."},
	{dirName = "Pods", markers = {"Podfile"}, inner = {"Manifest.lock"}, name = "CocoaPods", owner = "CocoaPods",
		what = "Installed pods. pod install restores them from Podfile.lock."},
	{dirName = ".venv", markers = {"pyproject.toml", "requirements.txt", "setup.py", "uv.lock"}, inner = {"pyvenv.cfg"}, name = "Python environment", owner = "Python",
		what = "A virtual environment with installed packages. uv sync, poetry install or pip install restores it."},
	{dirName = "venv", markers = {"pyproject.toml", "requirements.txt", "setup.py"}, inner = {"pyvenv.cfg"}, name = "Python environment", owner = "Python",
		what = "A virtual environment with installed packages. pip install -r requirements.txt restores it."},
	{dirName = ".dart_tool", markers = {"pubspec.yaml"}, inner = {"package_config.json"}, name = "Dart tool cache", owner = "Dart",
		what = "Resolved packages and build cache. dart pub get makes it again."},
	{dirName = ".next", markers = {"package.json"}, inner = {"BUILD_ID"}, name = "Next.js build", owner = "Next.js",
		what = "The compiled site. next build makes it again."},
	{dirName = ".turbo", markers = {"turbo.json"}, inner = {}, name = "Turborepo cache", owner = "Turborepo",
		what = "Cached task outputs. The next turbo run fills it again."},
	{dirName = ".godot", markers = {"project.godot"}, inner = {"imported"}, name = "Godot imports", owner = "Godot",
		what = "Imported assets and shader caches. Godot reimports them when the project opens."},
	{dirName = ".zig-cache", markers = {"build.zig"}, inner = {}, name = "Zig cache", owner = "Zig",
		what = "Compiled objects. zig build makes them again."},
	{dirName = "zig-out", markers = {"build.zig"}, inner = {}, name = "Zig output", owner = "Zig",
		what = "Built binaries. zig build makes them again."},
	{dirName = "_build", markers = {"mix.exs"}, inner = {}, name = "Mix build", owner = "Elixir",
		what = "Compiled BEAM files. mix compile makes them again."},
	{dirName = ".stack-work", markers = {"stack.yaml"}, inner = {}, name = "Stack build", owner = "Haskell Stack",
		what = "Compiled packages. stack build makes them again."},
	{dirName = "Library", markers = {"ProjectSettings"}, inner = {"ArtifactDB", "Artifacts"}, name = "Unity library", owner = "Unity",
		what = "Imported assets and the artifact database. Unity reimports the project when it opens, which can take long."},
}

-- Folder names a search for projects never descends into: generated output,
-- version control, Trash and app bundles.
Builds.skip = {".git", ".Trash", "node_modules", "Pods", ".build", "target", ".venv", "venv", "DerivedData", "Build",
	"build", ".next", ".turbo", ".godot", "_build", ".stack-work", ".dart_tool", ".zig-cache", "zig-out", ".cache",
	"Library", "*.app", "*.framework", "*.xcarchive", "*.photoslibrary", "*.bundle"}

-- How deep below a project root the search goes.
Builds.depth = 6

-- Folders where people keep their projects, relative to the home folder.
Builds.roots = {"Developer", "code", "Code", "Projects", "projects", "src", "dev", "repos", "GitHub", "Sites", "work", "Work"}

-- Unique folder names the rules describe.
function Builds.dirNames()
	local seen, names = {}, {}
	for _, rule in ipairs(Builds.rules) do
		if not seen[rule.dirName] then seen[rule.dirName] = true; table.insert(names, rule.dirName) end
	end
	return names
end

return Builds
