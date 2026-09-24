local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, assets, tool = D.item, D.group, D.cache, D.assets, D.tool
return function()
	return group("ai-agents", "AI agents", "AI coding tools, Apple Intelligence and Siri", "sparkles", "systemIndigo", {
		group("ai-tools", "AI coding tools", "Caches, conversations and work kept separate", "terminal", "systemIndigo", {
			tool("codex", "Codex", "~/.codex"), tool("opencode", "OpenCode", "~/.local/share/opencode"), tool("grok", "Grok", "~/.grok"),
			item("opencode-downloads", "OpenCode download cache", "Downloaded tools and model metadata", "~/.cache/opencode", cache),
			item("grok-support", "Grok application data", "Local app data if present; does not measure cloud conversations", "~/Library/Application Support/Grok"),
			item("grok-app-cache", "Grok application cache", "Review app-owned downloads before removing", "~/Library/Caches/ai.x.grok"),
			item("opencode-config", "OpenCode configuration", "Project and tool configuration; review only", "~/.opencode"),
			tool("claude", "Claude Code", "~/.claude"), tool("cursor", "Cursor", "~/Library/Application Support/Cursor"),
		}),
		group("intelligence", "Apple Intelligence & Siri", "On-device Apple models and Siri assets", "sparkles", "systemPurple", {
			assets("foundation-models", "Apple Intelligence models", "Language, visual and coding models; shared across features", "brain", "systemPurple", {"UAF_FM_GenerativeModels", "UAF_FM_Visual", "UAF_FM_CodeLM", "UAF_FM_Overrides", "UAF_IF_Planner", "UAF_IF_PlannerOverrides", "UAF_SummarizationKitConfiguration"}),
			assets("siri-assets", "Siri", "Understanding, responses, voice activation and dialogue", "waveform", "systemPurple", {"UAF_Siri_AnswerSynthesis", "UAF_Siri_DialogAssets", "UAF_Siri_FindMyConfigurationFiles", "UAF_Siri_PlatformAssets", "UAF_Siri_TextToSpeech", "UAF_Siri_Understanding", "UAF_Siri_UnderstandingASRHammer", "UAF_Siri_UnderstandingNLOverrides", "Trial_Siri_SiriDialogAssets", "Trial_Siri_SiriFindMyConfigurationFiles", "Trial_Siri_SiriTextToSpeech", "Trial_Siri_SiriUnderstandingAsrAssistant", "Trial_Siri_SiriUnderstandingAttentionAssets", "Trial_Siri_SiriUnderstandingMorphun", "Trial_Siri_SiriUnderstandingNL", "Trial_Siri_SiriUnderstandingNLOverrides", "VoiceTriggerAssetsASMac", "VoiceTriggerAssetsMac", "VoiceTriggerAssetsStudioDisplay"}),
		}),
	})
end
