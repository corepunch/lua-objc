-- A developer's Mac, synthetic: what `--showcase` shows and what the tests
-- measure. Every path, size and date here is invented; nothing is read from
-- a real disk. Sizes are bytes, dates are days before "now".
local GB, MB = 1e9, 1e6

return function(home)
	local now = os.time()
	local function ago(days) return now - math.floor(days * 86400) end
	local files, plists, repos = {}, {}, {}
	-- One file stands for a folder's contents: `file(path, bytes, days)`.
	local function file(path, bytes, days)
		path = path:gsub("^~", home)
		table.insert(files, {path = path, bytes = bytes, used = ago(days or 10)})
	end
	local function plist(path, value) plists[path:gsub("^~", home)] = value end

	-- Xcode
	local derived = "~/Library/Developer/Xcode/DerivedData/"
	file(derived .. "Birdsong-fxkqwrtyuiopasdfghjklzxcvbnmqw/Build/Products/Debug/Birdsong.app/Birdsong", 2.8 * GB, 3)
	plist(derived .. "Birdsong-fxkqwrtyuiopasdfghjklzxcvbnmqw/info.plist", {WorkspacePath = home .. "/Developer/Birdsong/Birdsong.xcodeproj"})
	file(derived .. "Tidepool-abcdefghijklmnopqrstuvwxyzabcd/Build/Intermediates.noindex/Tidepool.build/objects.o", 1.9 * GB, 140)
	plist(derived .. "Tidepool-abcdefghijklmnopqrstuvwxyzabcd/info.plist", {WorkspacePath = home .. "/Developer/old/Tidepool/Tidepool.xcworkspace"})
	file(derived .. "ModuleCache.noindex/ABCDEF/Foundation.pcm", 1.2 * GB, 1)
	file(derived .. "SymbolCache.noindex/symbols.db", 0.4 * GB, 2)
	file("~/Library/Developer/Xcode/iOS DeviceSupport/iPhone16,2 26.0.1 (23A350)/Symbols/usr/lib/dyld", 5.1 * GB, 12)
	file("~/Library/Developer/Xcode/iOS DeviceSupport/iPhone14,5 18.6 (22G86)/Symbols/usr/lib/dyld", 4.8 * GB, 210)
	file("~/Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)/Symbols/usr/lib/dyld", 4.2 * GB, 480)
	file("~/Library/Developer/Xcode/watchOS DeviceSupport/Watch7,4 26.0 (23R356)/Symbols/usr/lib/dyld", 1.1 * GB, 30)
	file("~/Library/Developer/Xcode/Archives/2026-06-14/Birdsong 14-06-2026, 10.12.xcarchive/Products/Applications/Birdsong.app/Birdsong", 180 * MB, 120)
	plist("~/Library/Developer/Xcode/Archives/2026-06-14/Birdsong 14-06-2026, 10.12.xcarchive/Info.plist", {Name = "Birdsong", CreationDate = "2026-06-14T08:12:00Z", ApplicationProperties = {CFBundleShortVersionString = "1.4", CFBundleVersion = "140"}})
	file("~/Library/Developer/Xcode/Archives/2026-09-30/Birdsong 30-09-2026, 16.40.xcarchive/Products/Applications/Birdsong.app/Birdsong", 210 * MB, 12)
	plist("~/Library/Developer/Xcode/Archives/2026-09-30/Birdsong 30-09-2026, 16.40.xcarchive/Info.plist", {Name = "Birdsong", CreationDate = "2026-09-30T14:40:00Z", ApplicationProperties = {CFBundleShortVersionString = "1.5", CFBundleVersion = "152"}})
	file("~/Library/Developer/Xcode/UserData/Previews/Simulator Devices/1111/data/x", 1.4 * GB, 6)
	file("~/Library/Developer/Xcode/DocumentationCache/v0/pages.db", 300 * MB, 20)
	file("~/Library/Caches/com.apple.dt.Xcode/Downloads/index.json", 200 * MB, 9)
	file("~/Library/Application Support/MobileSync/Backup/00008120-001A2B3C4D5E6F7G/Manifest.db", 11 * GB, 40)
	file("/Library/Developer/CommandLineTools/usr/bin/clang", 1.3 * GB, 300)

	-- Simulators
	local devices = "~/Library/Developer/CoreSimulator/Devices/"
	local iphone17, ipad, iphone15, watch, orphan = "9A4C2D7E-1F3B-4A5C-8D6E-0F1A2B3C4D5E", "7B3D1E5F-2A4C-4B6D-9E7F-1A2B3C4D5E6F",
		"5C2E0F4A-3B5D-4C7E-8F9A-2B3C4D5E6F7A", "3D1F9E3B-4C6E-4D8F-9A0B-3C4D5E6F7A8B", "1E0A8D2C-5D7F-4E9A-8B1C-4D5E6F7A8B9C"
	file(devices .. iphone17 .. "/data/Containers/Data/Application/1/Library/Caches/x", 4.9 * GB, 5)
	plist(devices .. iphone17 .. "/device.plist", {name = "iPhone 17", runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"})
	file(devices .. ipad .. "/data/Library/Caches/x", 3.6 * GB, 200)
	plist(devices .. ipad .. "/device.plist", {name = "iPad Pro 13-inch (M5)", runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"})
	file(devices .. iphone15 .. "/data/Library/Caches/x", 2.2 * GB, 400)
	plist(devices .. iphone15 .. "/device.plist", {name = "iPhone 15", runtime = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"})
	file(devices .. watch .. "/data/Library/Caches/x", 0.6 * GB, 60)
	plist(devices .. watch .. "/device.plist", {name = "Apple Watch Series 11 (46mm)", runtime = "com.apple.CoreSimulator.SimRuntime.watchOS-26-0"})
	file(devices .. orphan .. "/data/Library/Caches/x", 0.9 * GB, 500)
	plist(devices .. orphan .. "/device.plist", {name = "iPhone SE (3rd generation)", runtime = "com.apple.CoreSimulator.SimRuntime.iOS-17-5"})
	file("/Library/Developer/CoreSimulator/Caches/dyld/26A434/com.apple.dyld/dyld_sim_shared_cache_arm64", 3.1 * GB, 8)
	local simulators = {
		devices = {
			["com.apple.CoreSimulator.SimRuntime.iOS-26-0"] = {
				{udid = iphone17, name = "iPhone 17", state = "Shutdown", isAvailable = true, lastBootedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", ago(5)), deviceTypeIdentifier = "com.apple.CoreSimulator.SimDeviceType.iPhone-17", dataPath = home .. "/Library/Developer/CoreSimulator/Devices/" .. iphone17 .. "/data"},
				{udid = ipad, name = "iPad Pro 13-inch (M5)", state = "Shutdown", isAvailable = true, lastBootedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", ago(200)), deviceTypeIdentifier = "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5", dataPath = home .. "/Library/Developer/CoreSimulator/Devices/" .. ipad .. "/data"},
			},
			["com.apple.CoreSimulator.SimRuntime.iOS-18-6"] = {
				{udid = iphone15, name = "iPhone 15", state = "Shutdown", isAvailable = false, availabilityError = "runtime profile not found", deviceTypeIdentifier = "com.apple.CoreSimulator.SimDeviceType.iPhone-15", dataPath = home .. "/Library/Developer/CoreSimulator/Devices/" .. iphone15 .. "/data"},
			},
			["com.apple.CoreSimulator.SimRuntime.watchOS-26-0"] = {
				{udid = watch, name = "Apple Watch Series 11 (46mm)", state = "Shutdown", isAvailable = true, lastBootedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", ago(60)), deviceTypeIdentifier = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm", dataPath = home .. "/Library/Developer/CoreSimulator/Devices/" .. watch .. "/data"},
			},
		},
		runtimes = {
			["A1B2C3D4-0001-4000-8000-000000000001"] = {identifier = "A1B2C3D4-0001-4000-8000-000000000001", platformIdentifier = "com.apple.platform.iphonesimulator", runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-26-0", version = "26.0", build = "23A343", state = "Ready", deletable = true, sizeBytes = 8.1 * GB, lastUsedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", ago(5)), path = "/Library/Developer/CoreSimulator/Volumes/iOS_23A343"},
			["A1B2C3D4-0002-4000-8000-000000000002"] = {identifier = "A1B2C3D4-0002-4000-8000-000000000002", platformIdentifier = "com.apple.platform.iphonesimulator", runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-18-5", version = "18.5", build = "22F77", state = "Ready", deletable = true, sizeBytes = 7.2 * GB, lastUsedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", ago(150)), path = "/Library/Developer/CoreSimulator/Volumes/iOS_22F77"},
			["A1B2C3D4-0003-4000-8000-000000000003"] = {identifier = "A1B2C3D4-0003-4000-8000-000000000003", platformIdentifier = "com.apple.platform.watchsimulator", runtimeIdentifier = "com.apple.CoreSimulator.SimRuntime.watchOS-26-0", version = "26.0", build = "23R356", state = "Ready", deletable = false, sizeBytes = 3.4 * GB, lastUsedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", ago(60))},
		},
	}

	-- Projects in ~/Developer: a build folder beside each marker.
	file("~/Developer/Birdsong/Birdsong.xcodeproj/project.pbxproj", 200e3, 1)
	file("~/Developer/Birdsong/Sources/App.swift", 40e3, 1)
	file("~/Developer/Birdsong/Build/Intermediates.noindex/Birdsong.build/x.o", 900 * MB, 2)
	file("~/Developer/Birdsong/Build/Products/Debug/Birdsong.app/Birdsong", 60 * MB, 2)
	file("~/Developer/Birdsong/.git/HEAD", 1e3, 1)
	file("~/Developer/webshop/package.json", 2e3, 130)
	file("~/Developer/webshop/src/index.ts", 30e3, 130)
	file("~/Developer/webshop/node_modules/.package-lock.json", 500e3, 120)
	file("~/Developer/webshop/node_modules/react/index.js", 640 * MB, 120)
	file("~/Developer/webshop/.git/HEAD", 1e3, 12)
	file("~/Developer/rustle/Cargo.toml", 1e3, 4)
	file("~/Developer/rustle/src/main.rs", 20e3, 4)
	file("~/Developer/rustle/target/CACHEDIR.TAG", 200, 4)
	file("~/Developer/rustle/target/debug/rustle", 2.1 * GB, 4)
	file("~/Developer/rustle/.git/HEAD", 1e3, 4)
	file("~/Developer/meadow/CMakeLists.txt", 3e3, 310)
	file("~/Developer/meadow/src/main.cpp", 50e3, 310)
	file("~/Developer/meadow/build/CMakeCache.txt", 40e3, 300)
	file("~/Developer/meadow/build/meadow", 480 * MB, 300)
	file("~/Developer/tooling/Makefile", 2e3, 220)
	file("~/Developer/tooling/main.c", 9e3, 220)
	file("~/Developer/tooling/build/tooling", 350 * MB, 200)
	file("~/Developer/pyservice/pyproject.toml", 1e3, 45)
	file("~/Developer/pyservice/service/app.py", 12e3, 45)
	file("~/Developer/pyservice/.venv/pyvenv.cfg", 300, 45)
	file("~/Developer/pyservice/.venv/lib/python3.13/site-packages/numpy/core.so", 410 * MB, 45)

	-- Worktrees of webshop and rustle. A linked worktree has a `.git` file.
	file("~/Developer/webshop/.claude/worktrees/checkout-flow-1a2b/.git", 100, 12)
	file("~/Developer/webshop/.claude/worktrees/checkout-flow-1a2b/src/index.ts", 180 * MB, 12)
	file("~/.codex/worktrees/cart-fix/webshop/.git", 100, 1)
	file("~/.codex/worktrees/cart-fix/webshop/src/index.ts", 175 * MB, 1)
	file("~/Developer/rustle-experiment/.git", 100, 20)
	file("~/Developer/rustle-experiment/src/main.rs", 60 * MB, 20)
	repos[home .. "/Developer/webshop"] = {commonDir = home .. "/Developer/webshop/.git", branch = "main", head = "aaaa1111", worktrees = {
		{path = home .. "/Developer/webshop/.claude/worktrees/checkout-flow-1a2b", branch = "feature/checkout-flow", head = "bbbb2222", facts = {changes = 0, untracked = 0, unpublished = 0, merged = true, submodules = 0, activity = ago(12)}},
		{path = home .. "/.codex/worktrees/cart-fix/webshop", branch = "fix/cart-total", head = "cccc3333", facts = {changes = 3, untracked = 1, unpublished = 0, merged = false, submodules = 0, activity = ago(1)}},
		{path = home .. "/Developer/webshop/.claude/worktrees/gone-9f8e", branch = "feature/gone", head = "dddd4444", prunable = true},
	}}
	repos[home .. "/Developer/rustle"] = {commonDir = home .. "/Developer/rustle/.git", branch = "main", head = "eeee5555", worktrees = {
		{path = home .. "/Developer/rustle-experiment", branch = "experiment/simd", head = "ffff6666", facts = {changes = 0, untracked = 0, unpublished = 2, merged = false, submodules = 0, activity = ago(20)}},
	}}
	repos[home .. "/Developer/Birdsong"] = {commonDir = home .. "/Developer/Birdsong/.git", branch = "main", head = "0a0a0a0a", worktrees = {}}

	-- Packages
	file("~/.npm/_cacache/index-v5/aa/bb", 1.1 * GB, 15)
	file("~/Library/Caches/pip/http/aa/bb", 620 * MB, 9)
	file("~/Library/Caches/Homebrew/downloads/node.tar.gz", 410 * MB, 30)
	file("~/Library/Caches/org.swift.swiftpm/repositories/swift-argument-parser/objects", 230 * MB, 25)
	file("~/.cargo/registry/cache/index/serde.crate", 1.6 * GB, 4)
	file("~/.gradle/caches/modules-2/files-2.1/x.jar", 900 * MB, 80)
	file("~/.rustup/toolchains/stable-aarch64-apple-darwin/lib/librustc.dylib", 1.3 * GB, 4)
	file("~/.rustup/toolchains/nightly-2025-11-02-aarch64-apple-darwin/lib/librustc.dylib", 1.2 * GB, 330)
	file("~/.nvm/versions/node/v20.19.0/bin/node", 180 * MB, 200)
	file("~/.nvm/versions/node/v22.12.0/bin/node", 190 * MB, 20)
	file("/opt/homebrew/Cellar/node/24.1.0/bin/node", 2.4 * GB, 30)

	-- Editors
	local code = "~/Library/Application Support/Code/"
	file(code .. "Cache/Cache_Data/index", 160 * MB, 1)
	file(code .. "CachedData/abc123/main.js.code", 230 * MB, 2)
	file(code .. "CachedExtensionVSIXs/ms-vscode.cpptools-1.35.3", 530 * MB, 60)
	file(code .. "WebStorage/1/IndexedDB/x", 540 * MB, 3)
	file(code .. "User/workspaceStorage/0a1b2c/state.vscdb", 320 * MB, 7)
	file("~/Library/Caches/vscode-cpptools/ipch/x.ipch", 1.0 * GB, 5)
	file("~/.vscode/extensions/ms-vscode.cpptools-1.35.3-darwin-arm64/bin/cpptools", 250 * MB, 60)
	file("~/.vscode/extensions/vadimcn.vscode-lldb-1.11.0/lldb/bin/lldb", 130 * MB, 30)
	file("~/.vscode/extensions/vadimcn.vscode-lldb-1.10.0/lldb/bin/lldb", 130 * MB, 180)
	file("~/.vscode/extensions/sumneko.lua-3.19.1-darwin-arm64/server/bin/lua-language-server", 80 * MB, 45)
	file("~/Library/Application Support/Zed/node/node-v24.11.0-darwin-arm64/bin/node", 250 * MB, 40)
	file("~/Library/Application Support/Zed/languages/rust-analyzer/rust-analyzer", 140 * MB, 40)
	file("~/Library/Caches/dev.zed.Zed/x", 90 * MB, 2)
	file("~/Library/Logs/Zed/Zed.log", 10 * MB, 1)
	file("~/Library/Caches/JetBrains/CLion2025.2/caches/x", 1.1 * GB, 10)
	file("~/Library/Caches/JetBrains/CLion2024.3/caches/x", 0.9 * GB, 400)

	-- AI tools
	file("~/.codex/sessions/2026/10/rollout-1.jsonl", 2.3 * GB, 1)
	file("~/.codex/archived_sessions/rollout-0.jsonl", 0.9 * GB, 90)
	file("~/.codex/thread_history_1.sqlite", 1.5 * GB, 1)
	file("~/.codex/worktree-backups/orion-ui-20261004-120922/x", 0.4 * GB, 7)
	file("~/.codex/plugins/cache/x", 0.38 * GB, 20)
	file("~/.codex/generated_images/x.png", 0.25 * GB, 30)
	file("~/.codex/log/codex-tui.log", 20 * MB, 1)
	file("~/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle/PersistentDownloads/Codex.dmg", 1.6 * GB, 14)
	file("~/.cache/codex-runtimes/codex-primary-runtime/bin/codex", 1.8 * GB, 2)
	file("~/.claude/projects/-Users-appleseed-Developer-webshop/session.jsonl", 1.5 * GB, 1)
	file("~/.claude/plugins/cache/x", 20 * MB, 10)
	file("~/.claude/file-history/x", 10 * MB, 1)
	file("~/.claude/cache/x", 5 * MB, 1)
	file("~/Library/Application Support/Claude/Cache/Cache_Data/x", 320 * MB, 1)
	file("~/Library/Application Support/Claude/Code Cache/js/x", 210 * MB, 1)
	file("~/Library/Application Support/Claude/claude-code/2.1.293/cli.js", 220 * MB, 12)
	file("~/Library/Application Support/Claude/claude-code/2.1.295/cli.js", 220 * MB, 2)
	file("~/.local/share/opencode/opencode.db", 1.2 * GB, 3)
	file("~/.local/share/opencode/log/x.log", 110 * MB, 3)
	file("~/.local/share/opencode/snapshot/x", 90 * MB, 3)
	file("~/.cache/opencode/x", 10 * MB, 3)
	file("~/.grok/sessions/x.jsonl", 510 * MB, 20)
	file("~/.grok/downloads/x.zip", 430 * MB, 20)
	file("~/.ollama/models/blobs/sha256-aaaa", 9.4 * GB, 25)

	-- System Data
	local assets = "/System/Library/AssetsV2/com_apple_MobileAsset_"
	file(assets .. "iOSSimulatorRuntime/aaaa.asset/AssetData/x.dmg", 7.9 * GB, 5)
	file(assets .. "UAF_Siri_Understanding/bbbb.asset/AssetData/x", 4.9 * GB, 20)
	file(assets .. "AppleDeveloperDocumentation/cccc.asset/AssetData/x", 1.6 * GB, 20)
	file(assets .. "UAF_LinguisticData/dddd.asset/AssetData/x", 1.4 * GB, 20)
	file(assets .. "TTSAXResourceModelAssets/eeee.asset/AssetData/x", 0.64 * GB, 20)
	file(assets .. "UAF_Speech_AutomaticSpeechRecognition/ffff.asset/AssetData/x", 0.4 * GB, 20)
	file("~/Library/Caches/com.apple.Music/x", 60 * MB, 1)
	file("~/Library/Caches/com.google.Chrome/Default/Cache/x", 480 * MB, 1)
	file("~/Library/Caches/com.spotify.client/Storage/x", 310 * MB, 2)
	file("~/Library/Caches/com.oldvendor.gone/x", 220 * MB, 400)
	file("~/Library/Caches/GeoServices/x", 70 * MB, 1)
	file("/Library/Caches/com.apple.iconservices.store/x", 50 * MB, 1)
	file("~/Library/Logs/Xcode/x.log", 80 * MB, 1)
	file("~/Library/Logs/com.openai.codex/x.log", 70 * MB, 1)
	file("~/Library/Logs/CoreSimulator/x.log", 40 * MB, 1)
	file("~/Library/Logs/Claude/x.log", 20 * MB, 1)
	file("/private/var/db/diagnostics/Persist/x.tracev3", 2.5 * GB, 0.5)
	file("/private/var/db/uuidtext/00/x", 430 * MB, 1)
	file("/private/var/db/powerlog/Library/BatteryLife/x", 800 * MB, 0.2)
	file("/private/tmp/build-cache-x/objects/x.o", 1.5 * GB, 3)
	file("/private/tmp/test-env/lib/x", 900 * MB, 1)
	file("/private/tmp/scratch/notes.txt", 60 * MB, 30)
	file("/private/var/tmp/old-install/x", 30 * MB, 100)
	local tmpdir = "/private/var/folders/fg/z7bvq7qs1lvfv6mdjsnr5gz40000gn/T"
	file(tmpdir .. "/apply-binary-delta.aCRqVte9bh/x", 80 * MB, 2)
	file(tmpdir .. "/ltgold-question-spacing/x", 420 * MB, 1)
	file("/private/var/folders/fg/z7bvq7qs1lvfv6mdjsnr5gz40000gn/C/clang/ModuleCache/x.pcm", 390 * MB, 1)
	file("/private/var/folders/fg/z7bvq7qs1lvfv6mdjsnr5gz40000gn/C/com.apple.dt.Instruments/x", 120 * MB, 10)

	local volumes = {
		{name = "Macintosh HD", role = "System", bytes = 13.7 * GB},
		{name = "Preboot", role = "Preboot", bytes = 10.9 * GB},
		{name = "Recovery", role = "Recovery", bytes = 1.5 * GB},
		{name = "VM", role = "VM", bytes = 6.4 * GB},
		{name = "Update", role = "Update", bytes = 0.02 * GB},
	}
	local apps = {
		{path = "/Applications/Xcode.app", bundleId = "com.apple.dt.Xcode", name = "Xcode"},
		{path = "/Applications/Visual Studio Code.app", bundleId = "com.microsoft.VSCode", name = "Visual Studio Code"},
		{path = "/Applications/Zed.app", bundleId = "dev.zed.Zed", name = "Zed"},
		{path = "/Applications/Google Chrome.app", bundleId = "com.google.Chrome", name = "Google Chrome"},
		{path = "/Applications/Spotify.app", bundleId = "com.spotify.client", name = "Spotify"},
		{path = "/Applications/Claude.app", bundleId = "com.anthropic.claudefordesktop", name = "Claude"},
		{path = "/Applications/Codex.app", bundleId = "com.openai.codex", name = "Codex"},
	}
	return {files = files, plists = plists, repos = repos, simulators = simulators, volumes = volumes, apps = apps, tmpdir = tmpdir,
		capacityBytes = 494 * GB, otherBytes = 290 * GB, label = "Macintosh HD"}
end
