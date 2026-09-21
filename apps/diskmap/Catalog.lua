-- macOS storage knowledge. Paths identify ownership, never permission to delete.
-- Parent locations are residual buckets: the worker excludes every more-specific root.
local Catalog = {}
Catalog.version = 2
local function item(id, name, subtitle, path, options)
	local row = {id = id, name = name, subtitle = subtitle, path = path, policy = "Review", action = "finder"}
	for key, value in pairs(options or {}) do row[key] = value end
	return row
end
local function group(id, name, subtitle, icon, color, children)
	return {id = id, name = name, subtitle = subtitle, icon = icon, color = color, children = children}
end
local cache = {policy = "Rebuildable", action = "trash", automatic = true, consequence = "Quit the owning tool first. Cached downloads or generated build data will be regenerated; future builds and downloads may take longer. Moving to Trash does not free space until you empty it in Finder."}
local xcode = {action = "xcode", automatic = true, consequence = "Review in Xcode. Keep resources required by your projects and devices. Archives can contain irreplaceable release builds and debug symbols."}
local system = {policy = "System managed", action = "settings", consequence = "Managed by macOS. No manual deletion is offered. Changing a feature setting does not guarantee immediate removal of downloaded assets."}
-- Exact asset-class directories observed on macOS. Shared ASR belongs to speech,
-- not exclusively to Siri or Dictation. Unknown/new classes remain in the residual.
local function assets(id, name, subtitle, icon, color, classes)
	local children = {}
	for index, class in ipairs(classes) do
		children[#children + 1] = item(id .. "-" .. index, class:gsub("_", " "),
			"System-managed asset class · " .. name,
			"/System/Library/AssetsV2/com_apple_MobileAsset_" .. class, system)
		children[#children].automatic = true
	end
	return group(id, name, subtitle, icon, color, children)
end
local function tool(id, name, root)
	return group(id, name, "Recognized local data; personal work is never treated as cache", "terminal", "systemPurple", {
		item(id .. "-cache", "Cache", "Review the tool’s own storage controls", root .. "/cache"),
		item(id .. "-sessions", "Sessions & history", "Saved conversations and working history", root .. "/sessions"),
		item(id .. "-archives", "Archived sessions", "Retained conversations, not disposable cache", root .. "/archived_sessions"),
		item(id .. "-worktrees", "Worktrees", "May contain uncommitted source changes", root .. "/worktrees"),
		item(id .. "-images", "Generated images", "Created work and output assets", root .. "/generated_images"),
		item(id .. "-other", "Other tool data", "Settings, databases and unclassified tool content", root),
	})
end
function Catalog.tree(home)
	local tree = {
		group("applications", "Applications", "Installed apps; developer installations are counted under Developer", "app.fill", "systemBlue", {
			item("apps-system", "Installed applications", "Shared applications on this Mac", "/Applications"),
			item("apps-user", "Personal applications", "Applications installed for your account", "~/Applications"),
		}),
		group("developer", "Developer", "Xcode, AI coding tools, package managers and environments", "hammer.fill", "systemPurple", {
			group("xcode", "Xcode", "Simulators, SDKs, device support and build history", "hammer.fill", "systemBlue", {
				item("runtimes", "Simulator runtimes", "Installed runtime images; manage optional components in Xcode", "/Library/Developer/CoreSimulator/Images", xcode),
				item("runtimes-legacy", "Additional runtime bundles", "Runtime bundles registered by installed developer tools", "/Library/Developer/CoreSimulator/Profiles/Runtimes", xcode),
				item("simulators", "Simulator devices", "Installed test apps, settings and device data", "~/Library/Developer/CoreSimulator/Devices", xcode),
				item("derived", "Xcode DerivedData", "Rebuildable build products, indexes and logs", "~/Library/Developer/Xcode/DerivedData", cache),
				item("devices", "Device support", "Symbols used when debugging connected devices", "~/Library/Developer/Xcode/iOS DeviceSupport", xcode),
				item("archives", "Archives", "Release builds and debug symbols — review before removing", "~/Library/Developer/Xcode/Archives", xcode),
				item("xcode-app", "Xcode & bundled SDKs", "SDKs belong to this installation; do not remove them individually", "/Applications/Xcode.app", xcode),
				item("clt", "Command Line Tools", "Compilers, SDKs and development utilities", "/Library/Developer/CommandLineTools", xcode),
				assets("developer-assets", "Downloaded developer assets", "Documentation, simulator runtimes and optional toolchains", "hammer.fill", "systemBlue", {"AppleDeveloperDocumentation", "iOSSimulatorRuntime", "MetalToolchain", "SourceEditorAssets"}),
				item("documentation", "Developer documentation", "Downloaded reference documentation", "~/Library/Developer/Shared/Documentation", xcode),
			}),
			group("ai-tools", "AI coding tools", "Caches, conversations and work kept separate", "sparkles", "systemPurple", {
				tool("codex", "Codex", "~/.codex"), tool("opencode", "OpenCode", "~/.local/share/opencode"),
				item("opencode-config", "OpenCode configuration", "Project and tool configuration; review only", "~/.opencode"),
				item("claude", "Claude Code", "Conversations and configuration; review only", "~/.claude"),
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
				item("cursor", "Cursor", "Editor settings, conversations and local data", "~/Library/Application Support/Cursor"),
				item("jetbrains", "JetBrains", "IDE caches and project indexes", "~/Library/Caches/JetBrains"),
			}),
			group("containers", "Containers & virtual machines", "Owner-managed disks may contain databases and personal work", "shippingbox.fill", "systemOrange", {
				item("docker", "Docker Desktop", "Virtual disk, images, containers and persistent volumes", "~/Library/Containers/com.docker.docker", {action = "docker"}),
				item("colima", "Colima", "Virtual machines and container storage", "~/.colima"),
				item("parallels", "Parallels virtual machines", "Guest operating systems and their data", "~/Parallels"),
			}),
		}),
		group("documents", "Documents", "Personal documents, downloads and desktop files", "doc.fill", "systemGreen", {
			item("documents-user", "Documents", "Personal documents and projects", "~/Documents"),
			item("downloads", "Downloads", "Downloaded files, installers and archives", "~/Downloads"),
			item("desktop", "Desktop", "Files kept on your desktop", "~/Desktop"),
		}),
		group("media", "Photos & media", "Libraries and local media; manage library contents in their apps", "photo.fill", "systemOrange", {
			item("pictures", "Photos & pictures", "Photo libraries and image files", "~/Pictures"),
			item("music", "Music & audio", "Music libraries, recordings and projects", "~/Music"),
			item("movies", "Movies & video", "Video libraries and creative projects", "~/Movies"),
		}),
		group("system-data", "System Data", "macOS feature assets, application support, caches and diagnostics", "gearshape.2.fill", "systemRed", {
			group("intelligence", "Apple Intelligence & Siri", "On-device models, Siri, Dictation and downloaded voices", "sparkles", "systemPurple", {
				assets("foundation-models", "Apple Intelligence models", "Language, visual and coding models; shared across features", "brain", "systemPurple", {"UAF_FM_GenerativeModels", "UAF_FM_Visual", "UAF_FM_CodeLM", "UAF_FM_Overrides", "UAF_IF_Planner", "UAF_IF_PlannerOverrides", "UAF_SummarizationKitConfiguration"}),
				assets("siri-assets", "Siri", "Understanding, responses, voice activation and dialogue", "waveform", "systemPurple", {"UAF_Siri_AnswerSynthesis", "UAF_Siri_DialogAssets", "UAF_Siri_FindMyConfigurationFiles", "UAF_Siri_PlatformAssets", "UAF_Siri_TextToSpeech", "UAF_Siri_Understanding", "UAF_Siri_UnderstandingASRHammer", "UAF_Siri_UnderstandingNLOverrides", "Trial_Siri_SiriDialogAssets", "Trial_Siri_SiriFindMyConfigurationFiles", "Trial_Siri_SiriTextToSpeech", "Trial_Siri_SiriUnderstandingAsrAssistant", "Trial_Siri_SiriUnderstandingAttentionAssets", "Trial_Siri_SiriUnderstandingMorphun", "Trial_Siri_SiriUnderstandingNL", "Trial_Siri_SiriUnderstandingNLOverrides", "VoiceTriggerAssetsASMac", "VoiceTriggerAssetsMac", "VoiceTriggerAssetsStudioDisplay"}),
				assets("dictation", "Dictation & speech recognition", "Shared recognition models used by Dictation and voice features", "mic.fill", "systemBlue", {"EmbeddedSpeechMac", "SpeechEndpointMacOSAssets", "UAF_Speech_AutomaticSpeechRecognition"}),
				assets("voices", "Downloaded voices & Personal Voice", "Spoken content, accessibility and speech synthesis", "speaker.wave.2.fill", "systemTeal", {"MacinTalkVoiceAssets", "VoiceServicesVocalizerVoice", "VoiceServices_CombinedVocalizerVoices", "VoiceServices_CustomVoice", "VoiceServices_GryphonVoice", "VoiceServices_VoiceResources", "TTSAXResourceModelAssets"}),
				item("speech", "Built-in speech resources", "Speech engines and bundled voices; separate from downloaded assets", "/System/Library/Speech", system),
			}),
			group("feature-assets", "Other macOS features", "Downloaded resources attributed to known macOS features", "square.stack.3d.up.fill", "systemTeal", {
				assets("translation", "Translation", "Downloaded translation and speech translation models", "character.bubble.fill", "systemBlue", {"UAF_Translation_Assets", "SpeechTranslationAssets", "SpeechTranslationAssets2", "SpeechTranslationAssets3", "SpeechTranslationAssets4", "SpeechTranslationAssets5", "SpeechTranslationAssets6", "SpeechTranslationAssets7"}),
				assets("photos-models", "Photos & image intelligence", "Clean Up, spatial photos, image captions and media analysis", "photo.fill", "systemOrange", {"UAF_Photos_MagicCleanup", "UAF_Photos_SpatialPhotosRelive", "ImageCaptionModel", "VCPMobileAssets"}),
				assets("wallpapers", "Wallpapers", "Downloaded desktop and Safari backgrounds", "photo.on.rectangle", "systemTeal", {"DesktopPicture", "SafariBackgroundImage"}),
				assets("dictionaries", "Dictionaries & language resources", "Downloaded dictionaries and linguistic data", "book.fill", "systemOrange", {"DictionaryServices_dictionary3macOS", "DictionaryServices_dictionaryOSX", "LinguisticData", "UAF_LinguisticData", "MecabraDictionaryRapidUpdates"}),
				assets("fonts", "Downloaded fonts", "Optional font collections", "textformat", "systemPurple", {"Font6", "Font7", "Font8"}),
				assets("search-models", "Spotlight & suggestions", "Search resources and understanding models; excludes unmeasured indexes", "magnifyingglass", "systemBlue", {"SpotlightResources", "UAF_SearchQueryUnderstanding", "UAF_SearchQueryUnderstandingOverrides", "CoreSuggestions", "CoreSuggestionsModels", "ContextKit"}),
				assets("accessibility-assets", "Accessibility resources", "Icon recognition and background sounds", "accessibility", "systemBlue", {"AXIconVision", "ComfortSoundsAssets"}),
				assets("update-assets", "macOS update & recovery downloads", "System-managed update assets, separate from installed macOS", "arrow.down.circle.fill", "systemGray", {"MacRecoveryOSUpdate", "MacSoftwareUpdate", "MacSplatSoftwareUpdate", "SFRSoftwareUpdate"}),
				item("mobile-assets", "Other downloaded system assets", "Residual assets, staging and preinstalled resources without confident feature attribution", "/System/Library/AssetsV2", system),
			}),
			group("caches", "Caches", "Application and system caches, excluding separately listed tools", "externaldrive.fill", "systemGreen", {
				item("user-caches", "Application caches", "Review by owner; may include offline content", "~/Library/Caches"),
				item("system-caches", "Shared caches", "System-wide generated data", "/Library/Caches", system),
			}),
			group("logs", "Logs & diagnostics", "Logs, crash reports and diagnostic history", "doc.text.fill", "systemOrange", {
				item("user-logs", "Application logs", "Diagnostic history for your applications", "~/Library/Logs"),
				item("shared-logs", "System diagnostics", "Shared logs and crash reports", "/Library/Logs", system),
				item("private-logs", "System logs", "Operating system logs", "/private/var/log", system),
			}),
			item("temporary", "Temporary files", "System-managed temporary content; no blanket deletion", "/private/var/folders", {policy = system.policy, action = system.action, consequence = system.consequence, icon = "doc.fill", color = "systemYellow"}),
			item("support", "Application support", "Other app databases, documents and settings", "~/Library/Application Support"),
			item("app-containers", "Sandboxed application data", "Documents and settings belonging to sandboxed apps", "~/Library/Containers"),
			item("group-containers", "Shared application data", "Data shared by related apps", "~/Library/Group Containers"),
			item("mail", "Mail", "Downloaded messages and attachments; manage in Mail", "~/Library/Mail"),
			item("messages", "Messages", "Conversation history and attachments", "~/Library/Messages"),
		}),
		group("backups", "Backups", "Restore points and device backups are personal data", "clock.arrow.circlepath", "systemTeal", {
			item("device-backups", "iPhone & iPad backups", "Review connected-device backups in Finder", "~/Library/Application Support/MobileSync/Backup"),
			{id = "snapshots", name = "Local snapshots", subtitle = "Managed by Time Machine; file scans cannot measure exclusive allocation", icon = "clock.arrow.circlepath", policy = "System managed", action = "settings"},
		}),
		group("macos", "macOS", "Required system, boot and recovery data", "shield.fill", "systemGray", {
			item("system", "Operating system", "Protected macOS installation", "/System", system),
			item("preboot", "Preboot", "Boot support; never manually remove", "/System/Volumes/Preboot", system),
			item("recovery", "Recovery", "macOS recovery environment", "/System/Volumes/Recovery", system),
			item("vm", "Virtual memory", "Swap and system memory backing", "/private/var/vm", system),
		}),
		group("trash", "Trash", "Space remains occupied until Trash is emptied in Finder", "trash", "systemGray", {
			item("user-trash", "Your Trash", "Review before permanently removing files", "~/.Trash"),
		}),
	}
	local owners = {
		xcode = "com.apple.dt.Xcode", ["vscode-data"] = "com.microsoft.VSCode",
		["vscode-extensions"] = "com.microsoft.VSCode", cursor = "com.todesktop.230313mzl4w4u92",
		docker = "com.docker.docker", mail = "com.apple.mail", messages = "com.apple.MobileSMS",
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
return Catalog
