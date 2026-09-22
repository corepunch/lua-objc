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
	local children = {}
	for index, class in ipairs(classes) do
		children[#children + 1] = item(id .. "-" .. index, class:gsub("_", " "),
			"System-managed asset class · " .. name,
			"/System/Library/AssetsV2/com_apple_MobileAsset_" .. class, system)
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
return {item = item, group = group, cache = cache, xcode = xcode, system = system, assets = assets, tool = tool}
