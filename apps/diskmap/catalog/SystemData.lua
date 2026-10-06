local D = require("apps.diskmap.catalog.Definitions")
local item, group, system, assets = D.item, D.group, D.system, D.assets
-- A cache its app clears from its own settings; Diskmap only reveals it.
local function appCache(threshold, advice)
	return {nature = "cache", remover = "owner", threshold = threshold, advice = advice}
end
-- A cache its app rebuilds, removed in Finder once the app is quit.
local function quitFirst(threshold, advice)
	return {nature = "cache", remover = "finder", threshold = threshold, advice = advice}
end
return function()
	return group("system-data", "System Data", "macOS feature assets, application support, caches and diagnostics", "gearshape.2.fill", "systemRed", {
	group("speech-assets", "Speech & voices", "Dictation, speech recognition and downloaded voices", "waveform", "systemTeal", {
		assets("dictation", "Dictation & speech recognition", "Not using Dictation? Turn it off in Keyboard settings; other voice features may still keep these models", "mic.fill", "systemBlue", {"EmbeddedSpeechMac", "SpeechEndpointMacOSAssets", "UAF_Speech_AutomaticSpeechRecognition"}),
		assets("voices", "Downloaded voices & Personal Voice", "Remove voices you do not use in Accessibility > Read & Speak", "speaker.wave.2.fill", "systemTeal", {"MacinTalkVoiceAssets", "VoiceServicesVocalizerVoice", "VoiceServices_CombinedVocalizerVoices", "VoiceServices_CustomVoice", "VoiceServices_GryphonVoice", "VoiceServices_VoiceResources", "TTSAXResourceModelAssets"}),
		item("speech", "Built-in speech resources", "Speech engines and bundled voices; separate from downloaded assets", "/System/Library/Speech", system),
	}),
	group("feature-assets", "Other macOS features", "Downloaded resources attributed to known macOS features", "square.stack.3d.up.fill", "systemTeal", {
		assets("translation", "Translation", "Downloaded translation and speech translation models", "character.bubble.fill", "systemBlue", {"UAF_Translation_Assets", "SpeechTranslationAssets", "SpeechTranslationAssets2", "SpeechTranslationAssets3", "SpeechTranslationAssets4", "SpeechTranslationAssets5", "SpeechTranslationAssets6", "SpeechTranslationAssets7"}),
		assets("photos-models", "Photos & image intelligence", "Clean Up, spatial photos, image captions and media analysis", "photo.fill", "systemOrange", {"UAF_Photos_MagicCleanup", "UAF_Photos_SpatialPhotosRelive", "ImageCaptionModel", "VCPMobileAssets"}),
		item("aerials", "Aerial wallpapers", "Downloaded aerial screen savers and wallpapers; remove them in Wallpaper settings", "/Library/Application Support/com.apple.idleassetsd/Customer",
			{nature = "download", remover = "setting", settingsSection = "wallpaper", threshold = 2e9, advice = "Remove downloaded aerials in System Settings › Wallpaper. They download again when chosen."}),
		assets("wallpapers", "Wallpapers", "Downloaded desktop and Safari backgrounds", "photo.on.rectangle", "systemTeal", {"DesktopPicture", "SafariBackgroundImage"}),
		assets("dictionaries", "Dictionaries & language resources", "Downloaded dictionaries and linguistic data", "book.fill", "systemOrange", {"DictionaryServices_dictionary3macOS", "DictionaryServices_dictionaryOSX", "LinguisticData", "UAF_LinguisticData", "MecabraDictionaryRapidUpdates"}),
		assets("fonts", "Downloaded fonts", "Optional font collections", "textformat", "systemPurple", {"Font6", "Font7", "Font8"}),
		assets("search-models", "Spotlight & suggestions", "Search resources and understanding models; excludes unmeasured indexes", "magnifyingglass", "systemBlue", {"SpotlightResources", "UAF_SearchQueryUnderstanding", "UAF_SearchQueryUnderstandingOverrides", "CoreSuggestions", "CoreSuggestionsModels", "ContextKit"}),
		assets("accessibility-assets", "Accessibility resources", "Icon recognition and background sounds", "accessibility", "systemBlue", {"AXIconVision", "ComfortSoundsAssets"}),
		assets("update-assets", "macOS update & recovery downloads", "System-managed update assets, separate from installed macOS", "arrow.down.circle.fill", "systemGray", {"MacRecoveryOSUpdate", "MacSoftwareUpdate", "MacSplatSoftwareUpdate", "SFRSoftwareUpdate"}),
		item("mobile-assets", "Other downloaded system assets", "Residual assets, staging and preinstalled resources without confident feature attribution", "/System/Library/AssetsV2", system),
	}),
	group("caches", "Caches", "Application and system caches, excluding separately listed tools", "externaldrive.fill", "systemGreen", {
		item("chrome-cache", "Google Chrome cache", "Browser cache; sign out or clear from Chrome when keeping owner settings", "~/Library/Caches/Google/Chrome",
			appCache(500e6, "Clear browsing data from Chrome's privacy settings; browser cache size alone does not establish which data is safe to remove. Chrome rebuilds its cache as you browse.")),
		item("slack-cache", "Slack cache", "Application cache; use Help → Troubleshooting → Clear Cache and Restart", "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches",
			appCache(500e6, "Slack's Help › Troubleshooting › Clear Cache and Restart command rebuilds cached data in the owning app. Diskmap only reveals this location.")),
		item("slack-cache-appsupport", "Slack cache (standard install)", "Application cache; use Help → Troubleshooting → Clear Cache and Restart", "~/Library/Application Support/Slack/Cache",
			appCache(500e6, "Slack's Help › Troubleshooting › Clear Cache and Restart command rebuilds cached data in the owning app. Diskmap only reveals this location.")),
		item("spotify-cache", "Spotify cache", "Application cache; manage its cache-size setting in Spotify preferences", "~/Library/Caches/com.spotify.client",
			appCache(500e6, "Spotify manages its cache size in Settings › Storage, where it can also be cleared. Diskmap only reveals this location.")),
		item("adobe-media-cache", "Adobe media cache", "Shared Premiere Pro and After Effects media cache", "~/Library/Application Support/Adobe/Common/Media Cache Files",
			appCache(1e9, "Adobe shared media caches have reached tens or hundreds of gigabytes in user reports. Manage this cache through Premiere Pro > Settings > Media Cache or After Effects > Settings > Disk. Connect current source-media drives before cleaning cache database entries. Media cache locations can be customized, so Diskmap measures the default location only.")),
		item("adobe-caches", "Adobe application caches", "Adobe caches, including version-specific After Effects disk caches", "~/Library/Caches/Adobe",
			appCache(1e9, "After Effects disk caches have reached hundreds of gigabytes in user reports. Clear the active version in After Effects > Settings > Disk > Empty Disk Cache; cached frames rebuild, but each version has its own cache. Use each Adobe app's settings for its caches; custom folders outside this Adobe cache root are not measured.")),
		item("safari-cache", "Safari cache", "Web content cached by Safari", "~/Library/Caches/com.apple.Safari",
			appCache(1e9, "Clear it in Safari › Settings › Privacy › Manage Website Data, or with Develop › Empty Caches. Diskmap only reveals this location.")),
		item("edge-cache", "Microsoft Edge cache", "Browser cache", "~/Library/Caches/Microsoft Edge",
			appCache(1e9, "Clear browsing data from Edge's privacy settings; Edge rebuilds its cache as you browse.")),
		item("firefox-cache", "Firefox cache", "Browser cache for every Firefox profile", "~/Library/Caches/Firefox",
			appCache(1e9, "Clear cached web content in Firefox › Settings › Privacy & Security › Cookies and Site Data.")),
		item("brave-cache", "Brave cache", "Browser cache", "~/Library/Caches/BraveSoftware",
			appCache(1e9, "Clear browsing data from Brave's privacy settings.")),
		item("teams-cache", "Microsoft Teams cache", "Cached messages, images and web content", "~/Library/Containers/com.microsoft.teams2/Data/Library/Caches",
			quitFirst(1e9, "Quit Teams completely before removing anything here; Teams downloads what it needs again after you sign in.")),
		item("discord-cache", "Discord cache", "Cached images, videos and code", "~/Library/Application Support/discord/Cache",
			quitFirst(1e9, "Quit Discord first, then remove the cache in Finder. Discord rebuilds it as you use it.")),
		item("user-caches", "Application caches", "Caches of every app without a row of its own", "~/Library/Caches",
			{nature = "cache", remover = "owner", threshold = 5e9,
				advice = "The caches of apps without their own row. Clear a cache from the owning app; deleting a whole folder here can sign you out, lose offline downloads and slow the next launch. Folders of apps you deleted are listed on Applications."}),
		item("system-caches", "Shared caches", "System-wide generated data", "/Library/Caches", system),
	}),
	group("logs", "Logs & diagnostics", "Logs, crash reports and diagnostic history", "doc.text.fill", "systemOrange", {
		item("mail-logs", "Mail connection logs", "Optional diagnostic logs; review separately from saved mail", "~/Library/Containers/com.apple.mail/Data/Library/Logs/Mail",
			{nature = "log", remover = "owner", threshold = 100e6,
				advice = "Mail connection logs can grow very large when diagnostic logging is on. First turn off Window > Connection Doctor > Log Connection Activity, then inspect and remove logs with Show Logs. These are not messages; keep the Mail message store and local mailboxes."}),
		item("diagnostic-reports", "Crash reports", "Crash and diagnostic reports of your apps, as Console shows them", "~/Library/Logs/DiagnosticReports",
			{nature = "log", remover = "finder", threshold = 500e6,
				advice = "Crash and diagnostic reports Console lists under Crash Reports. Keep any you still need to send to a developer; the rest can be moved to the Trash in Finder."}),
		item("user-logs", "Application logs", "Diagnostic history for your applications", "~/Library/Logs",
			{nature = "log", remover = "finder", threshold = 2e9,
				advice = "Logs your apps write. Keep what you need to send to a developer; a folder that keeps growing belongs to an app that logs too much, so stop that first, then remove old logs in Finder."}),
		item("shared-logs", "System diagnostics", "Shared logs and crash reports", "/Library/Logs", system),
		item("private-logs", "System logs", "Operating system logs", "/private/var/log", system),
		item("unified-log", "Unified log", "The system log Console reads; macOS keeps it to a size budget", "/private/var/db/diagnostics", system),
		item("unified-log-strings", "Unified log strings", "Format strings the unified log refers to", "/private/var/db/uuidtext", system),
		item("power-log", "Power log", "Battery and energy history behind Battery settings", "/private/var/db/powerlog", system),
	}),
	item("temporary", "Temporary files", "Each account's temporary files and system caches; a restart clears stale ones", "/private/var/folders",
		{nature = "system", remover = "restart", threshold = 5e9, icon = "doc.fill", color = "systemYellow",
			advice = "Each account's $TMPDIR and caches such as Quick Look thumbnails and App Store downloads. Restart your Mac: macOS clears stale temporary files at startup. Do not delete these folders while you are logged in."}),
	item("support", "Application support", "Other app databases, documents and settings", "~/Library/Application Support"),
	item("app-containers", "Sandboxed application data", "Documents and settings belonging to sandboxed apps", "~/Library/Containers"),
	item("group-containers", "Shared application data", "Data shared by related apps", "~/Library/Group Containers"),
	-- Small per-app folders the Applications page adds to each app's data.
	item("preferences", "Preferences", "Every app's settings, one property list per app", "~/Library/Preferences", essential),
	item("saved-state", "Saved window state", "Windows apps reopen when they launch", "~/Library/Saved Application State",
		{nature = "cache", remover = "owner", advice = "Apps rewrite their saved windows as they quit. To stop it for every app, turn off “Close windows when quitting an application” in System Settings › Desktop & Dock."}),
	item("http-storages", "Network storage", "Cookies and responses apps keep from their network requests", "~/Library/HTTPStorages"),
	item("webkit-data", "Web view data", "Website data of apps that show web pages", "~/Library/WebKit"),
	item("library-user", "Other user library data", "Preferences and other local application data", "~/Library"),
	item("library-shared", "Other shared library data", "Shared application and system support files", "/Library"),
	item("private-other", "Other system working data", "System-managed databases and working files", "/private", system),
})
end
