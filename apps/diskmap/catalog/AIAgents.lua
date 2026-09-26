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
		-- Downloaded model weights are often the largest reclaimable developer
		-- data in 2026: tens of gigabytes per model, re-downloadable, never
		-- garbage-collected by the tools themselves.
		group("local-models", "Local AI models", "Downloaded model weights for Ollama, LM Studio, Hugging Face and PyTorch", "cpu", "systemIndigo", {
			item("ollama", "Ollama models", "Pulled models and their layers", "~/.ollama/models", {reviewThreshold = 5e9, consequence = "List models with ollama list and remove unused ones with ollama rm. Removed models download again with ollama pull."}),
			item("huggingface", "Hugging Face cache", "Models and datasets downloaded by transformers, diffusers and the hub", "~/.cache/huggingface", {reviewThreshold = 5e9, consequence = "Use huggingface-cli delete-cache to choose revisions to remove. Deleted models download again the next time code loads them."}),
			item("lmstudio", "LM Studio models", "Models downloaded in LM Studio", "~/.lmstudio/models", {reviewThreshold = 5e9, consequence = "Delete models you no longer run from LM Studio's My Models. They can be downloaded again."}),
			item("lmstudio-legacy", "LM Studio models (older location)", "Models downloaded by earlier LM Studio versions", "~/.cache/lm-studio", {reviewThreshold = 5e9, consequence = "Earlier LM Studio versions stored models here. Check LM Studio's models folder setting before removing anything."}),
			item("torch-hub", "PyTorch hub cache", "Pretrained weights downloaded by torch.hub and torchvision", "~/.cache/torch", {reviewThreshold = 2e9, consequence = "Weights download again the next time code requests them."}),
		}),
		group("intelligence", "Apple Intelligence & Siri", "On-device Apple models and Siri assets", "sparkles", "systemPurple", {
			assets("foundation-models", "Apple Intelligence models", "Language, visual and coding models; shared across features", "brain", "systemPurple", {"UAF_FM_GenerativeModels", "UAF_FM_Visual", "UAF_FM_CodeLM", "UAF_FM_Overrides", "UAF_IF_Planner", "UAF_IF_PlannerOverrides", "UAF_SummarizationKitConfiguration"}),
			assets("siri-assets", "Siri", "Understanding, responses, voice activation and dialogue", "waveform", "systemPurple", {"UAF_Siri_AnswerSynthesis", "UAF_Siri_DialogAssets", "UAF_Siri_FindMyConfigurationFiles", "UAF_Siri_PlatformAssets", "UAF_Siri_TextToSpeech", "UAF_Siri_Understanding", "UAF_Siri_UnderstandingASRHammer", "UAF_Siri_UnderstandingNLOverrides", "Trial_Siri_SiriDialogAssets", "Trial_Siri_SiriFindMyConfigurationFiles", "Trial_Siri_SiriTextToSpeech", "Trial_Siri_SiriUnderstandingAsrAssistant", "Trial_Siri_SiriUnderstandingAttentionAssets", "Trial_Siri_SiriUnderstandingMorphun", "Trial_Siri_SiriUnderstandingNL", "Trial_Siri_SiriUnderstandingNLOverrides", "VoiceTriggerAssetsASMac", "VoiceTriggerAssetsMac", "VoiceTriggerAssetsStudioDisplay"}),
		}),
	})
end
