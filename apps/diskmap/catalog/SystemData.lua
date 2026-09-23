local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("system-data", "System Data", "macOS feature assets, application support, caches and diagnostics", "gearshape.2.fill", "systemRed", {
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
		item("chrome-cache", "Google Chrome cache", "Browser cache; sign out or clear from Chrome when keeping owner settings", "~/Library/Caches/Google/Chrome", {reviewThreshold = 500e6, consequence = "Review in Chrome's site data and privacy controls before clearing; browser cache size alone does not establish which data is safe to remove."}),
		item("slack-cache", "Slack cache", "Application cache; use Help → Troubleshooting → Clear Cache and Restart", "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches", {reviewThreshold = 500e6, consequence = "Slack's Clear Cache and Restart command rebuilds cached data in the owning app. Diskmap only reveals this location."}),
		item("slack-cache-appsupport", "Slack cache (standard install)", "Application cache; use Help → Troubleshooting → Clear Cache and Restart", "~/Library/Application Support/Slack/Cache", {reviewThreshold = 500e6, consequence = "Slack's Clear Cache and Restart command rebuilds cached data in the owning app. Diskmap only reveals this location."}),
		item("spotify-cache", "Spotify cache", "Application cache; manage its cache-size setting in Spotify preferences", "~/Library/Caches/com.spotify.client", {reviewThreshold = 500e6, consequence = "Spotify manages cache size in its preferences. Diskmap only reveals this location and does not clear app data."}),
		item("adobe-media-cache", "Adobe media cache", "Shared Premiere Pro and After Effects media cache", "~/Library/Application Support/Adobe/Common/Media Cache Files", {reviewThreshold = 1e9, consequence = "Manage this cache through Premiere Pro > Settings > Media Cache or After Effects > Settings > Disk. Connect current source-media drives before cleaning cache database entries. Media cache locations can be customized, so Diskmap measures the default location only."}),
		item("adobe-caches", "Adobe application caches", "Adobe caches, including version-specific After Effects disk caches", "~/Library/Caches/Adobe", {reviewThreshold = 1e9, consequence = "Use each Adobe app's cache settings. For After Effects, clear the active version through Settings > Disk > Empty Disk Cache; older versions keep separate caches. Custom folders outside this root are not measured."}),
		item("user-caches", "Application caches", "Review by owner; may include offline content", "~/Library/Caches"),
		item("system-caches", "Shared caches", "System-wide generated data", "/Library/Caches", system),
	}),
	group("logs", "Logs & diagnostics", "Logs, crash reports and diagnostic history", "doc.text.fill", "systemOrange", {
		item("mail-logs", "Mail connection logs", "Optional diagnostic logs; review separately from saved mail", "~/Library/Containers/com.apple.mail/Data/Library/Logs/Mail", {reviewThreshold = 100e6, consequence = "In Mail, turn off Window > Connection Doctor > Log Connection Activity first. Then review or remove diagnostic logs using Show Logs. These are not messages; keep the Mail message store and local mailboxes."}),
		item("user-logs", "Application logs", "Diagnostic history for your applications", "~/Library/Logs"),
		item("shared-logs", "System diagnostics", "Shared logs and crash reports", "/Library/Logs", system),
		item("private-logs", "System logs", "Operating system logs", "/private/var/log", system),
	}),
	item("temporary", "Temporary files", "System-managed temporary content; no blanket deletion", "/private/var/folders", {policy = system.policy, action = system.action, consequence = system.consequence, icon = "doc.fill", color = "systemYellow"}),
	item("support", "Application support", "Other app databases, documents and settings", "~/Library/Application Support"),
	item("app-containers", "Sandboxed application data", "Documents and settings belonging to sandboxed apps", "~/Library/Containers"),
	item("group-containers", "Shared application data", "Data shared by related apps", "~/Library/Group Containers"),
	item("mail", "Mail", "Downloaded messages and attachments; manage in Mail", "~/Library/Mail"),
	item("library-user", "Other user library data", "Preferences and other local application data", "~/Library"),
	item("library-shared", "Other shared library data", "Shared application and system support files", "/Library"),
	item("private-other", "Other system working data", "System-managed databases and working files", "/private", system),
	item("messages", "Messages", "Conversation history and attachments", "~/Library/Messages"),
})
end
