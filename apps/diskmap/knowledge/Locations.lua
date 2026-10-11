-- Where developer tools and macOS put the data that fills a Mac: one line
-- per folder, with who owns it, what it is and whether it may go. This is
-- the whole dictionary Diskmap reads; everything else it says about a
-- folder is computed (VISION.md: conventions and measurements over tables).
--
-- Fields:
--   category  the page that lists it (knowledge/Categories)
--   section   the list on that page
--   path      "~" is the home folder
--   name      as the row shows it
--   owner     the tool or system that writes it, as a person knows it
--   what      one sentence: what it holds and what removing it means
--   remove    safe    rebuilt or downloaded again when needed; Diskmap can move it to the Trash
--             review  yours to decide: history, downloads, work; Diskmap can move it after review
--             owner   cleared from inside the owning app or its command; Diskmap opens the owner
--             system  macOS manages it; Diskmap explains it and does nothing
--   expand    list its immediate children as rows instead of itself (a
--             folder of per-app or per-tool folders)
--   children  notes for known children of an expanded folder, by name
--   admin     owned by root: Finder asks for an administrator to move it
--   settings  the System Settings pane that manages it (services/System openSettings)
--   checked   when the layout was last verified against the installed tool.
--             The long tail moves often (~/.codex, ~/.claude, ~/.cursor);
--             Apple's conventions move once a decade.
local Locations = {}

local APPLE = "2026-10"
local TOOLS = "2026-10"

local function entry(category, section, path, name, owner, what, remove, extra)
	local row = {category = category, section = section, path = path, name = name, owner = owner, what = what, remove = remove, checked = TOOLS}
	for key, value in pairs(extra or {}) do row[key] = value end
	return row
end
local function apple(category, section, path, name, owner, what, remove, extra)
	local row = entry(category, section, path, name, owner, what, remove, extra)
	row.checked = APPLE
	return row
end

Locations.list = {
	-- Xcode. DerivedData, device support, archives and simulator devices are
	-- read by services/Sources from their folders and simctl, so they are not
	-- here; these are the fixed caches around them.
	apple("xcode", "caches", "~/Library/Developer/Xcode/UserData/Previews", "SwiftUI previews", "Xcode",
		"Simulators and build products Xcode Previews keeps per project. Xcode rebuilds them the next time a preview runs.", "safe"),
	apple("xcode", "caches", "~/Library/Developer/Xcode/DocumentationCache", "Documentation cache", "Xcode",
		"Rendered documentation pages. Xcode rebuilds the cache as you read.", "safe"),
	apple("xcode", "caches", "~/Library/Developer/Xcode/DocumentationIndex", "Documentation index", "Xcode",
		"The search index of the documentation viewer. Xcode rebuilds it.", "safe"),
	apple("xcode", "caches", "~/Library/Developer/Xcode/iOS Device Logs", "Device logs", "Xcode",
		"Console logs Xcode copied from connected devices. Useful only while you debug the sessions they came from.", "safe"),
	apple("xcode", "caches", "~/Library/Developer/Xcode/DeviceLogs", "Device logs", "Xcode",
		"Console logs Xcode copied from connected devices. Useful only while you debug the sessions they came from.", "safe"),
	apple("xcode", "caches", "~/Library/Caches/com.apple.dt.Xcode", "Xcode cache", "Xcode",
		"Downloads and indexes Xcode keeps outside DerivedData. Xcode rebuilds it.", "safe"),
	apple("xcode", "caches", "~/Library/Developer/XCTestDevices", "Test devices", "Xcode",
		"Simulator clones Xcode makes to run tests in parallel. Xcode recreates them for the next test run.", "safe"),
	apple("xcode", "caches", "~/Library/Developer/CoreSimulator/Caches", "Simulator caches", "Simulator",
		"Caches of your simulator devices. The simulator rebuilds them on its next boot.", "safe"),
	apple("xcode", "backups", "~/Library/Application Support/MobileSync/Backup", "Device backups", "Finder",
		"Backups of iPhones and iPads made with Finder, one folder per device. Finder › Manage Backups removes one; a backup is the only copy of that device's data.", "owner", {expand = true}),
	apple("xcode", "tools", "/Library/Developer/CommandLineTools", "Command Line Tools", "Xcode",
		"The compilers and SDKs behind git, clang and swift in Terminal. Xcode brings its own; xcode-select -p says which is in use.", "review", {admin = true}),

	-- Simulators. Devices and runtimes come from simctl; this is the shared
	-- cache beside them.
	apple("simulators", "caches", "/Library/Developer/CoreSimulator/Caches", "Runtime caches", "Simulator",
		"The dyld shared caches the simulator builds per runtime. Rebuilt the next time a simulator boots; owned by root, so Finder asks for an administrator.", "safe", {admin = true}),

	-- Package managers: downloaded packages a lockfile restores.
	entry("packages", "caches", "~/.npm/_cacache", "npm cache", "npm", "Downloaded packages. npm fetches them again on install.", "safe"),
	entry("packages", "caches", "~/Library/pnpm/store", "pnpm store", "pnpm", "The content-addressed store every pnpm project links into. pnpm fetches missing packages again on install.", "safe"),
	entry("packages", "caches", "~/.local/share/pnpm/store", "pnpm store", "pnpm", "The content-addressed store every pnpm project links into. pnpm fetches missing packages again on install.", "safe"),
	entry("packages", "caches", "~/Library/Caches/Yarn", "Yarn cache", "Yarn", "Downloaded packages. Yarn fetches them again on install.", "safe"),
	entry("packages", "caches", "~/.bun/install/cache", "Bun cache", "Bun", "Downloaded packages. Bun fetches them again on install.", "safe"),
	entry("packages", "caches", "~/Library/Caches/pip", "pip cache", "pip", "Downloaded wheels and source archives. pip downloads them again on install.", "safe"),
	entry("packages", "caches", "~/.cache/uv", "uv cache", "uv", "Downloaded wheels and built packages. uv downloads them again on sync.", "safe"),
	entry("packages", "caches", "~/Library/Caches/pypoetry", "Poetry cache", "Poetry", "Downloaded packages. Poetry downloads them again on install.", "safe"),
	entry("packages", "caches", "~/Library/Caches/Homebrew", "Homebrew downloads", "Homebrew", "Downloaded bottles and source archives. brew downloads them again when needed; brew cleanup does the same.", "safe"),
	entry("packages", "caches", "~/Library/Caches/org.swift.swiftpm", "Swift package cache", "Swift Package Manager", "Cloned package repositories shared by every project. Resolved again from the Package.resolved files.", "safe"),
	entry("packages", "caches", "~/Library/Caches/CocoaPods", "CocoaPods cache", "CocoaPods", "Downloaded pods. pod install downloads them again.", "safe"),
	entry("packages", "caches", "~/.cocoapods/repos", "CocoaPods specs", "CocoaPods", "Clones of the podspec repositories. pod install restores them; the CDN source needs none.", "safe"),
	entry("packages", "caches", "~/.cargo/registry", "Cargo registry", "Cargo", "Downloaded crates and the registry index. cargo fetches them again on build.", "safe"),
	entry("packages", "caches", "~/.cargo/git", "Cargo git checkouts", "Cargo", "Dependencies fetched from Git. cargo clones them again on build.", "safe"),
	entry("packages", "caches", "~/.gradle/caches", "Gradle caches", "Gradle", "Downloaded dependencies and build caches. Gradle downloads them again on build.", "safe"),
	entry("packages", "caches", "~/.m2/repository", "Maven repository", "Maven", "Downloaded dependencies. Maven downloads them again on build.", "safe"),
	entry("packages", "caches", "~/go/pkg/mod", "Go module cache", "Go", "Downloaded modules. go build downloads them again; go clean -modcache does the same.", "safe"),
	entry("packages", "caches", "~/Library/Caches/go-build", "Go build cache", "Go", "Compiled packages. go build recompiles what it needs.", "safe"),
	entry("packages", "caches", "~/.cache/deno", "Deno cache", "Deno", "Downloaded modules. Deno downloads them again on run.", "safe"),
	entry("packages", "caches", "~/Library/Caches/node-gyp", "node-gyp headers", "node-gyp", "Node headers downloaded to compile native modules. Downloaded again when a module compiles.", "safe"),
	entry("packages", "caches", "~/Library/Caches/ms-playwright", "Playwright browsers", "Playwright", "Browser builds Playwright downloaded for tests, one per version. npx playwright install downloads the current ones again.", "review"),
	entry("packages", "caches", "~/Library/Caches/Cypress", "Cypress binaries", "Cypress", "Cypress app versions, one per version installed. The current one is downloaded again by cypress install.", "review"),
	entry("packages", "toolchains", "~/.rustup/toolchains", "Rust toolchains", "rustup", "Installed Rust versions. rustup toolchain list names them; the one your projects use stays.", "review", {expand = true}),
	entry("packages", "toolchains", "~/.nvm/versions/node", "Node versions", "nvm", "Installed Node versions. nvm uninstall removes one; the one your projects use stays.", "review", {expand = true}),
	entry("packages", "toolchains", "~/.pyenv/versions", "Python versions", "pyenv", "Installed Python versions. pyenv uninstall removes one; the one your projects use stays.", "review", {expand = true}),
	entry("packages", "toolchains", "~/.local/share/mise/installs", "mise installs", "mise", "Tool versions mise installed. mise uninstall removes one.", "review", {expand = true}),
	entry("packages", "toolchains", "~/.sdkman/candidates", "SDKMAN candidates", "SDKMAN", "JDKs and tools SDKMAN installed. sdk uninstall removes one.", "review", {expand = true}),
	entry("packages", "toolchains", "~/Library/Android/sdk", "Android SDK", "Android Studio", "Platforms, system images and build tools. Remove old platforms and images from Android Studio's SDK Manager.", "owner"),
	entry("packages", "toolchains", "/opt/homebrew", "Homebrew", "Homebrew", "Installed formulae and casks. brew autoremove and brew cleanup remove what nothing needs; Diskmap does not touch installed packages.", "owner"),
	entry("packages", "toolchains", "/usr/local", "Local tools", "Installers", "Command-line tools installers put here outside Homebrew. Remove one with the tool's own uninstaller.", "owner"),

	-- Editors: caches the editor rebuilds and the extensions it installed.
	entry("editors", "vscode", "~/Library/Application Support/Code/Cache", "Cache", "Visual Studio Code", "Web content cache. Rebuilt as you use the editor.", "safe"),
	entry("editors", "vscode", "~/Library/Application Support/Code/CachedData", "Cached data", "Visual Studio Code", "Compiled JavaScript of the editor and its extensions, per version. Rebuilt at launch.", "safe"),
	entry("editors", "vscode", "~/Library/Application Support/Code/CachedExtensionVSIXs", "Downloaded extension installers", "Visual Studio Code", "The .vsix files of extensions you installed. Not needed once installed; downloaded again on reinstall.", "safe"),
	entry("editors", "vscode", "~/Library/Application Support/Code/Code Cache", "Code cache", "Visual Studio Code", "Compiled web code. Rebuilt at launch.", "safe"),
	entry("editors", "vscode", "~/Library/Application Support/Code/GPUCache", "GPU cache", "Visual Studio Code", "Shader cache. Rebuilt at launch.", "safe"),
	entry("editors", "vscode", "~/Library/Application Support/Code/WebStorage", "Web storage", "Visual Studio Code", "Local storage of extensions' web views, such as signed-in chats. Removing it signs those extensions out.", "review"),
	entry("editors", "vscode", "~/Library/Application Support/Code/User/workspaceStorage", "Workspace storage", "Visual Studio Code", "Per-workspace state: open editors, extension data, search history. Folders of workspaces you no longer open are safe to remove.", "review"),
	entry("editors", "vscode", "~/Library/Caches/vscode-cpptools", "C/C++ extension cache", "Visual Studio Code", "IntelliSense databases of the C/C++ extension. Rebuilt the next time a project opens.", "safe"),
	entry("editors", "vscode", "~/.vscode/extensions", "Extensions", "Visual Studio Code", "Installed extensions, one folder per version. An older version beside a newer one is a leftover; the current ones are managed from the Extensions view.", "review", {expand = true, versions = true}),
	entry("editors", "zed", "~/Library/Application Support/Zed/node", "Node runtime", "Zed", "The Node version Zed downloaded to run language servers. Zed downloads it again when missing.", "safe"),
	entry("editors", "zed", "~/Library/Application Support/Zed/languages", "Language servers", "Zed", "Language servers Zed downloaded, one per language. Zed downloads them again when a file of that language opens.", "safe"),
	entry("editors", "zed", "~/Library/Caches/dev.zed.Zed", "Zed cache", "Zed", "Zed's cache. Rebuilt as you use the editor.", "safe"),
	entry("editors", "zed", "~/Library/Logs/Zed", "Zed logs", "Zed", "Zed's logs. Old ones can go.", "safe"),
	entry("editors", "cursor", "~/Library/Application Support/Cursor/Cache", "Cache", "Cursor", "Web content cache. Rebuilt as you use the editor.", "safe"),
	entry("editors", "cursor", "~/Library/Application Support/Cursor/CachedData", "Cached data", "Cursor", "Compiled JavaScript of the editor and its extensions, per version. Rebuilt at launch.", "safe"),
	entry("editors", "cursor", "~/Library/Application Support/Cursor/CachedExtensionVSIXs", "Downloaded extension installers", "Cursor", "The .vsix files of extensions you installed. Not needed once installed.", "safe"),
	entry("editors", "cursor", "~/Library/Application Support/Cursor/User/workspaceStorage", "Workspace storage", "Cursor", "Per-workspace state. Folders of workspaces you no longer open are safe to remove.", "review"),
	entry("editors", "cursor", "~/.cursor/extensions", "Extensions", "Cursor", "Installed extensions, one folder per version. An older version beside a newer one is a leftover.", "review", {expand = true, versions = true}),
	entry("editors", "jetbrains", "~/Library/Caches/JetBrains", "JetBrains caches", "JetBrains", "Indexes and caches of IntelliJ, PyCharm, CLion and the others, one folder per product version. A version you no longer have installed is a leftover; the IDE rebuilds its own.", "safe", {expand = true}),
	entry("editors", "jetbrains", "~/Library/Logs/JetBrains", "JetBrains logs", "JetBrains", "IDE logs, one folder per product version. Old ones can go.", "safe"),
	entry("editors", "jetbrains", "~/Library/Caches/Google/AndroidStudio", "Android Studio caches", "Android Studio", "Indexes and caches. The IDE rebuilds them.", "safe"),

	-- AI tools: the long tail. Conversation history is the person's to
	-- decide; caches and downloaded runtimes are not.
	entry("ai", "codex", "~/.codex", "Codex data", "Codex", "Codex's sessions, plugins, worktrees and generated files.", "review", {expand = true, children = {
		sessions = {what = "Conversation transcripts, one file per session. Codex reads them to resume a session; archived ones are kept separately.", remove = "review"},
		archived_sessions = {what = "Transcripts of sessions you archived. Codex no longer lists them.", remove = "review"},
		["thread_history_1.sqlite"] = {what = "The index of your conversations.", remove = "review"},
		worktrees = {what = "Git worktrees Codex made for tasks. The Worktrees page lists each with its Git state.", remove = "review"},
		["worktree-backups"] = {what = "Copies Codex kept of worktrees before changing them.", remove = "review"},
		plugins = {what = "Installed plugins and their cache. Codex downloads a plugin again when it is enabled.", remove = "review"},
		generated_images = {what = "Images Codex generated in conversations.", remove = "review"},
		visualizations = {what = "Charts and diagrams Codex generated in conversations.", remove = "review"},
		skills = {what = "Skills you installed.", remove = "review"},
		log = {what = "Codex's logs. Old ones can go.", remove = "safe"},
		logs = {what = "Codex's logs. Old ones can go.", remove = "safe"},
		tmp = {what = "Temporary files of sessions.", remove = "safe"},
	}}),
	entry("ai", "codex", "~/Library/Caches/com.openai.codex", "Codex app cache", "Codex", "The Codex app's cache, including the updater's downloads of previous versions. Rebuilt as needed.", "safe"),
	entry("ai", "codex", "~/.cache/codex-runtimes", "Codex runtimes", "Codex", "The runtime the Codex app downloaded to run its agent. Downloaded again when the app needs it.", "safe"),
	entry("ai", "codex", "~/Library/Caches/Codex", "Codex cache", "Codex", "Codex's cache. Rebuilt as needed.", "safe"),
	entry("ai", "claude", "~/.claude", "Claude Code data", "Claude Code", "Claude Code's transcripts, plugins and settings.", "review", {expand = true, children = {
		projects = {what = "Conversation transcripts per project folder. Claude Code reads them to resume a session.", remove = "review"},
		["file-history"] = {what = "Copies of files before Claude Code edited them, for undo.", remove = "review"},
		plugins = {what = "Installed plugins and their cache.", remove = "review"},
		cache = {what = "Claude Code's cache. Rebuilt as needed.", remove = "safe"},
		["shell-snapshots"] = {what = "Shell environment snapshots sessions start from. Recreated per session.", remove = "safe"},
		telemetry = {what = "Usage telemetry queued for upload.", remove = "safe"},
		backups = {what = "Backups of settings files.", remove = "review"},
		worktrees = {what = "Git worktrees Claude Code made for tasks. The Worktrees page lists each with its Git state.", remove = "review"},
	}}),
	entry("ai", "claude", "~/Library/Application Support/Claude/Cache", "Claude app cache", "Claude", "Web content cache of the Claude app. Rebuilt as you use it.", "safe"),
	entry("ai", "claude", "~/Library/Application Support/Claude/Code Cache", "Claude app code cache", "Claude", "Compiled web code of the Claude app. Rebuilt at launch.", "safe"),
	entry("ai", "claude", "~/Library/Application Support/Claude/claude-code", "Bundled Claude Code versions", "Claude", "Claude Code versions the Claude app installed for its Code tab, one folder per version. The app downloads the current one again.", "review", {expand = true, versions = true}),
	entry("ai", "opencode", "~/.local/share/opencode", "OpenCode data", "OpenCode", "OpenCode's conversation database, logs and snapshots.", "review", {expand = true, children = {
		["opencode.db"] = {what = "Every conversation and message. OpenCode reads it to show your history.", remove = "review"},
		log = {what = "OpenCode's logs. Old ones can go.", remove = "safe"},
		snapshot = {what = "Snapshots of files before OpenCode changed them, for undo.", remove = "review"},
		storage = {what = "Session storage.", remove = "review"},
	}}),
	entry("ai", "opencode", "~/.cache/opencode", "OpenCode cache", "OpenCode", "OpenCode's cache. Rebuilt as needed.", "safe"),
	entry("ai", "opencode", "~/.opencode", "OpenCode install", "OpenCode", "The OpenCode binary and its Node modules as installed by its installer. Reinstalling restores them.", "review"),
	entry("ai", "grok", "~/.grok", "Grok data", "Grok", "Grok's sessions, downloads and memory.", "review", {expand = true, children = {
		sessions = {what = "Conversation transcripts.", remove = "review"},
		downloads = {what = "Files Grok downloaded for sessions.", remove = "review"},
		["marketplace-cache"] = {what = "Cache of the plugin marketplace. Downloaded again when browsed.", remove = "safe"},
		logs = {what = "Grok's logs. Old ones can go.", remove = "safe"},
	}}),
	entry("ai", "models", "~/.ollama/models", "Ollama models", "Ollama", "Downloaded model weights, several gigabytes each. ollama rm removes one; ollama pull downloads it again.", "owner"),
	entry("ai", "models", "~/.lmstudio/models", "LM Studio models", "LM Studio", "Downloaded model weights. Remove them from LM Studio's My Models.", "owner"),
	entry("ai", "models", "~/.cache/lm-studio", "LM Studio cache", "LM Studio", "LM Studio's cache. Rebuilt as needed.", "safe"),
	entry("ai", "models", "~/.cache/huggingface", "Hugging Face cache", "Hugging Face", "Models and datasets Python libraries downloaded from the Hub. Downloaded again on the next use.", "review"),
	entry("ai", "models", "~/.cache/torch", "PyTorch cache", "PyTorch", "Pretrained weights torch.hub downloaded. Downloaded again on the next use.", "review"),

	-- System Data: what macOS Storage lumps together. Volumes come from
	-- diskutil (services/Sources), since their files are clones that add up
	-- to more than the volume holds.
	apple("system", "assets", "/System/Library/AssetsV2", "Downloaded system assets", "macOS",
		"Models, voices, dictionaries and simulator runtimes macOS downloaded when a feature needed them. macOS manages the store; turning a feature off lets it remove that feature's assets.", "system", {expand = true, children = {
			com_apple_MobileAsset_iOSSimulatorRuntime = {name = "iOS simulator runtimes", what = "iOS simulator runtimes, as downloaded. The Simulators page lists each runtime; deleting one there removes it here.", remove = "system"},
			com_apple_MobileAsset_watchOSSimulatorRuntime = {name = "watchOS simulator runtimes", what = "watchOS simulator runtimes, as downloaded. Manage them on the Simulators page.", remove = "system"},
			com_apple_MobileAsset_tvOSSimulatorRuntime = {name = "tvOS simulator runtimes", what = "tvOS simulator runtimes, as downloaded. Manage them on the Simulators page.", remove = "system"},
			com_apple_MobileAsset_xrOSSimulatorRuntime = {name = "visionOS simulator runtimes", what = "visionOS simulator runtimes, as downloaded. Manage them on the Simulators page.", remove = "system"},
			com_apple_MobileAsset_AppleDeveloperDocumentation = {name = "Developer documentation", what = "Offline developer documentation Xcode downloaded. Remove it in Xcode › Settings › Components.", remove = "owner"},
			com_apple_MobileAsset_UAF_Siri_Understanding = {name = "Siri understanding", what = "Siri's on-device speech and language understanding. Removed by macOS when Siri is turned off.", remove = "system", settings = "siri"},
			com_apple_MobileAsset_UAF_LinguisticData = {name = "Dictionaries and text prediction", what = "Dictionaries, spell checking and text prediction for your languages.", remove = "system"},
			com_apple_MobileAsset_UAF_FM_GenerativeModels = {name = "Apple Intelligence model", what = "The on-device Apple Intelligence language model.", remove = "system", settings = "intelligence"},
			com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition = {name = "Dictation speech recognition", what = "Dictation's speech recognition models.", remove = "system", settings = "dictation"},
			com_apple_MobileAsset_VoiceServices_CombinedVocalizerVoices = {name = "Siri and spoken content voices", what = "Downloaded voices for Siri and spoken content. Manage them in Accessibility › Spoken Content.", remove = "system", settings = "voices"},
			com_apple_MobileAsset_TTSAXResourceModelAssets = {name = "Spoken content voices", what = "Spoken content voices. Manage them in Accessibility › Spoken Content.", remove = "system", settings = "voices"},
			com_apple_MobileAsset_MacSoftwareUpdate = {name = "Downloaded macOS update", what = "A downloaded macOS update waiting to install. Installing or removing it in Software Update clears it.", remove = "system", settings = "softwareupdate"},
		}}),
	apple("system", "caches", "~/Library/Caches", "Your caches", "macOS",
		"Caches of your apps, one folder per app. An app rebuilds its cache; quit it first.", "safe", {expand = true, owners = true}),
	apple("system", "caches", "/Library/Caches", "Shared caches", "macOS",
		"Caches of apps installed for everyone. Owned by root, so Finder asks for an administrator.", "safe", {expand = true, owners = true, admin = true}),
	apple("system", "logs", "~/Library/Logs", "Your logs", "macOS",
		"Logs and crash reports of your apps, one folder per app. Old ones can go.", "safe", {expand = true, owners = true}),
	apple("system", "logs", "/Library/Logs", "Shared logs", "macOS",
		"Diagnostic reports and install logs. Owned by root.", "review", {admin = true}),
	apple("system", "logs", "/private/var/db/diagnostics", "Unified log", "macOS",
		"The system log Console reads. macOS keeps it to a size budget; sudo log erase clears it early.", "system"),
	apple("system", "logs", "/private/var/db/uuidtext", "Unified log strings", "macOS",
		"Format strings the unified log refers to. It grows and shrinks with the log.", "system"),
	apple("system", "logs", "/private/var/db/powerlog", "Power log", "macOS",
		"Battery and energy history behind Battery settings. macOS trims it.", "system"),
	apple("system", "temporary", "/private/tmp", "Temporary files", "Command-line tools",
		"Scratch files of tools and scripts; /tmp is a link here. macOS removes files untouched for three days, and a restart empties it. A tool still running would lose its working files.", "review", {expand = true}),
	apple("system", "temporary", "/private/var/tmp", "Persistent temporary files", "Command-line tools",
		"Temporary files meant to survive a restart. macOS removes old ones periodically.", "review", {expand = true}),
	apple("system", "temporary", "$TMPDIR", "Your temporary items", "macOS",
		"Your account's TMPDIR, where apps and tools keep files for one session. macOS removes files untouched for three days.", "review", {expand = true}),
	apple("system", "temporary", "$TMPDIR/../C", "Your app caches", "macOS",
		"Per-account caches macOS keeps for apps and compilers, such as clang's module cache. Rebuilt when needed.", "safe", {expand = true, owners = true}),
}

-- The locations of `category`, in listing order.
function Locations.of(category)
	local rows = {}
	for _, row in ipairs(Locations.list) do
		if row.category == category then table.insert(rows, row) end
	end
	return rows
end

return Locations
