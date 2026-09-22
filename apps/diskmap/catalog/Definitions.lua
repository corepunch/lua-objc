local function item(id, name, subtitle, path, options)
	local row = {id = id, name = name, subtitle = subtitle, path = path, policy = "Review", action = "finder"}
	for key, value in pairs(options or {}) do row[key] = value end
	return row
end
local function group(id, name, subtitle, icon, color, children)
	return {id = id, name = name, subtitle = subtitle, icon = icon, color = color, children = children}
end
local cache = {policy = "Rebuildable", action = "trash", consequence = "Quit the owning tool first. Cached downloads or generated build data will be regenerated; future builds and downloads may take longer. Moving to Trash does not free space until you empty it in Finder."}
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
		children[#children + 1] = item(id .. "-" .. index, class:gsub("_", " "),
			"System-managed asset class · " .. name,
			"/System/Library/AssetsV2/com_apple_MobileAsset_" .. class, system)
		if guidance[id] then
			children[#children].settingsSection = guidance[id][1]
			children[#children].consequence = guidance[id][2]
			children[#children].reviewThreshold = 100e6
		end
	end
	return group(id, name, subtitle, icon, color, children)
end
local function tool(id, name, root)
	local specs = {
		{"cache", "Download cache", "/cache", "Rebuildable downloads; quit the tool before clearing", cache},
		{"plugins", "Plugins", "/plugins", "Installed integrations and their dependencies; reinstall may be required"},
		{"models", "Models & downloads", "/models", "Local models and downloads; review before removing"},
		{"logs", "Logs", id == "opencode" and "/log" or "/logs", "Diagnostic history; may be needed for troubleshooting"},
		{"databases", "Databases", "/sqlite", "Conversation indexes and persistent state; never disposable cache"},
		{"sessions", "Sessions & history", id == "opencode" and "/storage" or "/sessions", "Saved conversations and working history"},
		{"archives", "Archived sessions", "/archived_sessions", "Retained conversations, not disposable cache"},
		{"worktrees", "Worktrees", id == "opencode" and "/repos" or "/worktrees", "May contain uncommitted source changes"},
		{"images", "Generated images", "/generated_images", "Created work and output assets"},
		{"assets", "Generated assets", id == "opencode" and "/tool-output" or "/visualizations", "Generated output; inspect before removing"},
		{"snapshots", "Snapshots", id == "opencode" and "/snapshot" or "/shell_snapshots", "Recovery and execution history; review before removing"},
		{"skills", "Skills", "/skills", "User-authored instructions and installed skills"},
		{"settings", "Settings", "/config.toml", "Tool configuration; preserve credentials and preferences"},
		{"auth", "Credentials", "/auth.json", "Authentication state; contents are never read"},
		{"other", "Root metadata & hidden files", "", "Residual after individually measured children; never treated as cache"},
	}
	local children = {}
	for _, spec in ipairs(specs) do
		local row = item(id .. "-" .. spec[1], spec[2], spec[4], root .. spec[3], spec[5])
		row.agent = id
		children[#children + 1] = row
	end
	return group(id, name, "Paths and data types; sessions and worktrees require review", "terminal", "systemPurple", children)
end
return {item = item, group = group, cache = cache, xcode = xcode, system = system, assets = assets, tool = tool}
