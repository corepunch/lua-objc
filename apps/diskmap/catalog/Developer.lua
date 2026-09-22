local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("developer", "Developer", "Xcode, AI coding tools, package managers and environments", "hammer.fill", "systemPurple", {
	item("projects", "Developer projects", "Source repositories and local build outputs", "~/Developer"),
	item("usr-local", "Local development tools", "Locally installed command-line tools and packages", "/usr/local"),
	group("xcode", "Xcode", "Simulators, SDKs, device support and build history", "hammer.fill", "systemBlue", {
		group("runtimes", "Simulator runtimes", "Keep installed operating systems required for simulator development", "iphone", "systemBlue", {
			item("runtime-images", "Runtime disk images", "CoreSimulator image storage", "/Library/Developer/CoreSimulator/Images", {policy = "Essential", action = "finder"}),
			item("runtime-bundles", "Runtime bundles", "Registered simulator operating systems", "/Library/Developer/CoreSimulator/Profiles/Runtimes", {policy = "Essential"}),
			item("runtime-assets", "iOS runtime downloads", "System-managed iOSSimulatorRuntime assets; retained by default", "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime", {policy = "Essential", action = "finder"}),
		}),
		item("simulators", "Simulator devices", "Installed test apps, settings and device data — manage without Xcode", "~/Library/Developer/CoreSimulator/Devices", {action = "simulators", consequence = "Erase removes installed test apps, accounts and device data. Delete also removes the device. Installed runtimes are preserved. Shut down a running device first."}),
		item("derived", "Xcode DerivedData", "Rebuildable build products, indexes and logs", "~/Library/Developer/Xcode/DerivedData", cache),
		item("devices", "Device support", "Symbols used when debugging connected devices", "~/Library/Developer/Xcode/iOS DeviceSupport", xcode),
		item("archives", "Archives", "Release builds and debug symbols — review before removing", "~/Library/Developer/Xcode/Archives", xcode),
		item("xcode-app", "Xcode & bundled SDKs", "SDKs belong to this installation; do not remove them individually", "/Applications/Xcode.app", xcode),
		item("clt", "Command Line Tools", "Compilers, SDKs and development utilities", "/Library/Developer/CommandLineTools", xcode),
		assets("developer-assets", "Downloaded developer assets", "Documentation, simulator runtimes and optional toolchains", "hammer.fill", "systemBlue", {"MetalToolchain", "SourceEditorAssets"}),
		item("documentation", "Offline developer documentation", "Downloaded reference documentation; online documentation remains available", "~/Library/Developer/Shared/Documentation", {action = "trash", policy = "Rebuildable", consequence = "Quit developer tools first. Removes offline documentation; download it again when needed. Moving to Trash does not free space until Finder empties it."}),
		item("documentation-assets", "Offline Apple documentation", "AppleDeveloperDocumentation downloaded by macOS", "/System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation", {action = "settings", settingsSection = "storage", consequence = "Review Developer storage in System Settings to remove optional offline documentation where offered. Online documentation remains available. Protected asset files are managed by macOS."}),
	}),
	group("ai-tools", "AI coding tools", "Caches, conversations and work kept separate", "sparkles", "systemPurple", {
		tool("codex", "Codex", "~/.codex"), tool("opencode", "OpenCode", "~/.local/share/opencode"), tool("grok", "Grok", "~/.grok"),
		item("opencode-downloads", "OpenCode download cache", "Downloaded tools and model metadata", "~/.cache/opencode", cache),
		item("grok-support", "Grok application data", "Local app data if present; does not measure cloud conversations", "~/Library/Application Support/Grok"),
		item("grok-app-cache", "Grok application cache", "Review app-owned downloads before removing", "~/Library/Caches/ai.x.grok"),
		item("opencode-config", "OpenCode configuration", "Project and tool configuration; review only", "~/.opencode"),
		tool("claude", "Claude Code", "~/.claude"),
	}),
	group("packages", "Package managers", "Downloaded packages are separate from installed environments", "shippingbox", "systemOrange", {
		item("npm", "npm downloads", "Content-addressed package download cache", "~/.npm/_cacache", cache),
		item("pip", "Python package downloads", "Cached wheels and downloaded packages", "~/Library/Caches/pip", cache),
		item("brew", "Homebrew downloads", "Cached bottles; installed packages are preserved", "~/Library/Caches/Homebrew", cache),
		item("brew-install", "Homebrew installation", "Installed packages and environments", "/opt/homebrew"),
		item("cargo", "Rust registry", "Downloaded crates and registry indexes", "~/.cargo/registry"),
		item("gradle", "Gradle", "Build caches and tool distributions", "~/.gradle"),
		item("maven", "Maven repository", "Downloaded and locally published artifacts", "~/.m2/repository"),
		item("go", "Go modules", "Downloaded module sources", "~/go/pkg/mod"),
	}),
	group("editors", "Editors & IDEs", "Application data can include settings and unsaved work", "curlybraces", "systemBlue", {
		group("vscode-data", "Visual Studio Code", "Caches separated from settings and unsaved work", "curlybraces", "systemBlue", {
			item("vscode-cache", "VS Code cache", "Rebuildable Chromium cache; review in the owning editor", "~/Library/Application Support/Code/Cache"),
			item("vscode-cached-data", "VS Code compiled code cache", "Generated JavaScript compilation data", "~/Library/Application Support/Code/CachedData"),
			item("vscode-gpu-cache", "VS Code GPU cache", "Generated graphics data", "~/Library/Application Support/Code/GPUCache"),
			item("vscode", "VS Code settings & work", "Settings, databases and recovery data; excludes listed caches", "~/Library/Application Support/Code"),
		}),
		item("vscode-extensions", "VS Code extensions", "Installed editor extensions", "~/.vscode/extensions"),
		tool("cursor", "Cursor", "~/Library/Application Support/Cursor"),
		item("jetbrains", "JetBrains", "IDE caches and project indexes", "~/Library/Caches/JetBrains"),
	}),
	group("containers", "Containers & virtual machines", "Owner-managed disks may contain databases and personal work", "shippingbox.fill", "systemOrange", {
		item("docker", "Docker Desktop", "Virtual disk, images, containers and persistent volumes", "~/Library/Containers/com.docker.docker", {action = "docker"}),
		item("colima", "Colima", "Virtual machines and container storage", "~/.colima"),
		item("parallels", "Parallels virtual machines", "Guest operating systems and their data", "~/Parallels"),
	}),
})
end
