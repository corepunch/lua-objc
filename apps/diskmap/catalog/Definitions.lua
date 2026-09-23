local function item(id, name, subtitle, path, options)
	local row = {id = id, name = name, subtitle = subtitle, path = path, policy = "Review", action = "finder"}
	for key, value in pairs(options or {}) do row[key] = value end
	return row
end
local function group(id, name, subtitle, icon, color, children)
	return {id = id, name = name, subtitle = subtitle, icon = icon, color = color, children = children}
end
local function generated(markerFile, dirName, options)
	local rule = {markerFile = markerFile, dirName = dirName}
	for key, value in pairs(options or {}) do rule[key] = value end
	return rule
end
local cache = {policy = "Rebuildable", action = "trash", consequence = "Quit the owning tool first. Cached downloads or generated build data will be regenerated; future builds and downloads may take longer. Moving to Trash does not free space until you empty it in Finder."}
local ownerCache = {
	policy = "Rebuildable", action = "ownerCleanup",
	consequence = "Diskmap asks the package manager to clear its own cache. Packages may need to be downloaded again, and future installs can take longer.",
}
local xcode = {action = "xcode", consequence = "Review in Xcode. Keep resources required by your projects and devices. Archives can contain irreplaceable release builds and debug symbols."}
local system = {policy = "System managed", action = "settings", consequence = "Managed by macOS. No manual deletion is offered. Changing a feature setting does not guarantee immediate removal of downloaded assets."}
-- Exact asset-class directories observed on macOS. Shared ASR belongs to speech,
-- not exclusively to Siri or Dictation. Unknown/new classes remain in the residual.
local function assets(id, name, subtitle, icon, color, classes)
	local guidance = {
		["siri-assets"] = {"siri", "Turning off Siri stops assistant requests and voice activation. Shared speech models can remain for other features; disabling Siri does not guarantee asset removal."},
		dictation = {"dictation", "Turning off Dictation stops voice-to-text keyboard input. Shared recognition models may still serve other voice features, so no immediate storage recovery is promised."},
		voices = {"voices", "In Accessibility > Read & Speak, manage system voices and remove unused downloaded voices. Removed voices will no longer be available offline. Preserve any Personal Voice you need."},
		["foundation-models"] = {"siri", "Turning off Apple Intelligence disables its on-device features. macOS manages model removal; this is not a guaranteed reclaim estimate."},
	}
	local children = {}
	for index, class in ipairs(classes) do
		table.insert(children, (item(id .. "-" .. index, class:gsub("_", " "),
			"System-managed asset class · " .. name,
			"/System/Library/AssetsV2/com_apple_MobileAsset_" .. class, system)))
		if guidance[id] then
			children[#children].settingsSection = guidance[id][1]
			children[#children].consequence = guidance[id][2]
			children[#children].reviewThreshold = 100e6
		end
	end
	return group(id, name, subtitle, icon, color, children)
end
local function tool(id, name, root)
	-- Curated per-tool layouts verified against installed products. Children
	-- that do not exist measure as missing; version drift inside a tool root
	-- is picked up by name through AgentFiles discovery, never guessed here.
	local catalogs = {
		codex = {
			{"cache", "Download cache", "/cache", "Rebuildable downloads; quit the tool before clearing", cache},
			{"sessions", "Sessions & rollouts", "/sessions", "Saved rollouts and conversation history; review old sessions in Codex and keep what you still need"},
			{"archives", "Archived sessions", "/archived_sessions", "Retained session history; review before removing"},
			{"worktrees", "Worktrees", "/worktrees", "May contain uncommitted source changes; never inferred to be a cache"},
			{"plugins", "Plugins", "/plugins", "Installed integrations and their dependencies; reinstall may be required"},
			{"skills", "Skills", "/skills", "User-authored instructions and installed skills; review only"},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children, including diagnostic databases; never treated as cache"},
		},
		opencode = {
			{"snapshots", "Snapshots", "/snapshot", "Tracks working trees for restore points; can retain orphaned temporary packs after interrupted operations"},
			{"logs", "Logs", "/log", "Diagnostic history; may be needed for troubleshooting"},
			{"sessions", "Sessions & history", "/storage", "Saved conversations and working history; review old sessions in OpenCode"},
			{"worktrees", "Worktrees", "/repos", "May contain uncommitted source changes; never inferred to be a cache"},
			{"assets", "Generated assets", "/tool-output", "Generated output; inspect before removing"},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children, including the main database; never treated as cache"},
		},
		claude = {
			{"projects", "Session transcripts", "/projects", "Conversations organized by project; review old sessions in Claude Code after moving durable notes elsewhere"},
			{"history", "File history & checkpoints", "/file-history", "Recovery checkpoints; can balloon during stuck sessions, so review before removing"},
			{"plugins", "Plugins", "/plugins", "Installed integrations and their dependencies; reinstall may be required"},
			{"cache", "Download cache", "/cache", "Rebuildable downloads; quit the tool before clearing", cache},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children, including debug logs and settings; never treated as cache"},
		},
		cursor = {
			{"cache", "Cursor cache", "/Cache", "Rebuildable Chromium cache; review in the owning editor", cache},
			{"cached-data", "Cursor compiled code cache", "/CachedData", "Generated compilation data", cache},
			{"gpu-cache", "Cursor GPU cache", "/GPUCache", "Generated graphics data", cache},
			{"other", "Cursor settings & work", "", "Settings, databases and recovery data; excludes listed caches"},
		},
		grok = {
			{"cache", "Download cache", "/cache", "Rebuildable downloads; quit the tool before clearing", cache},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children; never treated as cache"},
		},
	}
	local specs = assert(catalogs[id], "Unknown AI tool layout: " .. tostring(id))
	local children = {}
	for _, spec in ipairs(specs) do
		local row = item(id .. "-" .. spec[1], spec[2], spec[4], root .. spec[3], spec[5])
		row.agent = id
		table.insert(children, row)
	end
	return group(id, name, "Paths and data types; sessions and worktrees require review", "terminal", "systemPurple", children)
end
return {item = item, group = group, generated = generated, cache = cache, ownerCache = ownerCache, xcode = xcode, system = system, assets = assets, tool = tool}
