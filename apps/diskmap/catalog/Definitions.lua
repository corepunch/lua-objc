-- The catalog's dictionary entries. Every location says what it is and who
-- removes it, in two words, and Clean Up derives everything else from them:
--
--   nature     what the data is: cache (made again by itself), build,
--              download (fetched again when needed, nobody chose it),
--              library (content you chose and use: games, models, sound
--              libraries, offline media, installed versions), log,
--              leftover, appData, personal, system
--   remover    who removes it: trash (Diskmap moves it to the Trash),
--              ownerCommand (Diskmap runs the owner's cleanup command, named
--              by `commandId`), owner (the owning app or tool, by hand),
--              setting (System Settings), restart (a restart clears it),
--              update (finishing the pending update clears it), finder (you,
--              in Finder), none (nothing removes it; context only)
--   threshold  the measured size at which Clean Up suggests it; nil never
--   advice     the one text that says how to clear it and what that costs
--
-- `policy` (the label every list shows) and `action` (what a row's button
-- does) follow from nature and remover (Locations.classify) unless an entry
-- names its own. A rule never widens what Diskmap may delete: only
-- `remover = "trash"` entries can be moved to the Trash, and only entries
-- with a `commandId` run a command.
local function item(id, name, subtitle, path, options)
	local row = {id = id, name = name, subtitle = subtitle, path = path}
	for key, value in pairs(options or {}) do row[key] = value end
	return row
end
-- `options.page` names the sidebar page that presents a resource and
-- everything under it (Location:destination in models/Locations.lua); opening it goes there.
local function group(id, name, subtitle, icon, color, children, options)
	local row = {id = id, name = name, subtitle = subtitle, icon = icon, color = color, children = children}
	for key, value in pairs(options or {}) do row[key] = value end
	return row
end
-- A generated folder beside one of its project `markers` (any one proves
-- the project). `inner` files inside the folder are a second proof that the
-- tool wrote it; with both, a `rebuildable` rule's folders move from Review
-- to Rebuildable.
local function generated(markers, dirName, options)
	local rule = {markers = type(markers) == "table" and markers or {markers}, dirName = dirName, inner = {}}
	for key, value in pairs(options or {}) do rule[key] = value end
	return rule
end
-- `options` with `extra` fields added, leaving the shared table unchanged.
local function with(options, extra)
	local merged = {}
	for key, value in pairs(options) do merged[key] = value end
	for key, value in pairs(extra) do merged[key] = value end
	return merged
end
-- A cache Diskmap may move to the Trash once its owner is quit.
local cache = {nature = "cache", remover = "trash", threshold = 500e6,
	advice = "Quit the owning tool first. Cached downloads or generated build data will be regenerated; future builds and downloads may take longer. Moving to Trash does not free space until you empty it in Finder."}
-- A cache its package manager clears on Diskmap's request.
local ownerCache = {nature = "cache", remover = "ownerCommand", threshold = 500e6,
	advice = "Diskmap asks the package manager to clear its own cache. Packages may need to be downloaded again, and future installs can take longer."}
-- Data macOS manages itself: context in Clean Up, never a suggestion.
local system = {nature = "system", remover = "none", action = "settings",
	advice = "Managed by macOS. No manual deletion is offered. Changing a feature setting does not guarantee immediate removal of downloaded assets."}
-- Data an app needs to work; never offered, whatever its size.
local essential = {nature = "appData", remover = "none", policy = "Essential"}
-- Exact asset-class directories observed on macOS. Shared ASR belongs to speech,
-- not exclusively to Siri or Dictation. Unknown/new classes remain in the residual.
-- A feature macOS manages from Settings says in its subtitle what to do, on
-- the group and on each class, since either can be the row a person reads:
-- a size alone left testers asking whether to turn Siri off. Only voices are
-- removed one by one in Settings; the others stay context, since turning a
-- feature off promises nothing.
local function assets(id, name, subtitle, icon, color, classes)
	local guidance = {
		["siri-assets"] = {section = "siri", advice = "Turning off Siri stops assistant requests and voice activation. Shared speech models can remain for other features; disabling Siri does not guarantee asset removal."},
		dictation = {section = "dictation", advice = "Turning off Dictation stops voice-to-text keyboard input. Shared recognition models may still serve other voice features, so no immediate storage recovery is promised."},
		voices = {section = "voices", nature = "download", remover = "setting", threshold = 500e6,
			advice = "In Accessibility > Read & Speak, manage system voices and remove unused downloaded voices. Removed voices will no longer be available offline. Preserve any Personal Voice you need."},
		["foundation-models"] = {section = "siri", advice = "Turning off Apple Intelligence disables its on-device features. macOS manages model removal; this is not a guaranteed reclaim estimate."},
	}
	local children = {}
	for index, class in ipairs(classes) do
		local guide = guidance[id]
		local row = item(id .. "-" .. index, class:gsub("_", " "), guide and subtitle or "System-managed asset class · " .. name,
			"/System/Library/AssetsV2/com_apple_MobileAsset_" .. class, system)
		if guide then
			row.settingsSection, row.advice = guide.section, guide.advice
			row.nature, row.remover, row.threshold = guide.nature or row.nature, guide.remover or row.remover, guide.threshold
		end
		table.insert(children, row)
	end
	return group(id, name, subtitle, icon, color, children)
end
local function tool(id, name, root)
	-- Curated per-tool layouts verified against installed products. Children
	-- that do not exist measure as missing; version drift inside a tool root
	-- is picked up by name through AgentFiles discovery, never guessed here.
	-- Sessions and history are reviewed in the tool; worktrees one by one on
	-- the Worktrees page; plugins, skills and settings are never suggested.
	local sessions = {nature = "appData", remover = "owner", threshold = 1e9}
	local keep = {nature = "personal", remover = "owner"}
	local other = {nature = "appData", remover = "none"}
	local catalogs = {
		codex = {
			{"cache", "Download cache", "/cache", "Rebuildable downloads; quit the tool before clearing", cache},
			{"sessions", "Sessions & rollouts", "/sessions", "Saved rollouts and conversation history", with(sessions, {advice = "Session rollouts accumulate without bound, including completed subagent histories. Review old sessions in Codex and keep conversations you still need."})},
			{"archives", "Archived sessions", "/archived_sessions", "Retained session history", with(sessions, {advice = "Archived sessions stay until you remove them. Review them in Codex and keep conversations you still need."})},
			{"worktrees", "Worktrees", "/worktrees", "May contain uncommitted source changes; never inferred to be a cache", keep},
			{"plugins", "Plugins", "/plugins", "Installed integrations and their dependencies; reinstall may be required", other},
			{"skills", "Skills", "/skills", "User-authored instructions and installed skills; review only", keep},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children, including diagnostic databases; never treated as cache", other},
		},
		opencode = {
			{"snapshots", "Snapshots", "/snapshot", "Tracks working trees for restore points", with(sessions, {advice = "Snapshot storage tracks working trees and can retain orphaned temporary packs after interrupted operations. Review snapshot contents in OpenCode; snapshots rebuild on next use."})},
			{"logs", "Logs", "/log", "Diagnostic history", {nature = "log", remover = "finder", threshold = 500e6, advice = "Diagnostic logs OpenCode writes. Keep recent ones for troubleshooting; older ones can be moved to the Trash in Finder."}},
			{"sessions", "Sessions & history", "/storage", "Saved conversations and working history", with(sessions, {advice = "Saved conversations and working history. Review old sessions in OpenCode and keep what you still need."})},
			{"worktrees", "Worktrees", "/repos", "May contain uncommitted source changes; never inferred to be a cache", keep},
			{"assets", "Generated assets", "/tool-output", "Generated output", {nature = "appData", remover = "finder", threshold = 1e9, advice = "Output the tool generated for you. Inspect it in Finder and keep what you still use."}},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children, including the main database; never treated as cache", other},
		},
		claude = {
			{"projects", "Session transcripts", "/projects", "Conversations organized by project", with(sessions, {advice = "Session transcripts accumulate per project. Review old entries in Claude Code after moving durable notes elsewhere."})},
			{"history", "File history & checkpoints", "/file-history", "Recovery checkpoints", with(sessions, {advice = "File-history checkpoints can balloon during stuck sessions. Review old entries in Claude Code after moving durable notes elsewhere."})},
			{"plugins", "Plugins", "/plugins", "Installed integrations and their dependencies; reinstall may be required", other},
			{"cache", "Download cache", "/cache", "Rebuildable downloads; quit the tool before clearing", cache},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children, including debug logs and settings; never treated as cache", other},
		},
		cursor = {
			{"cache", "Cursor cache", "/Cache", "Rebuildable Chromium cache", cache},
			{"cached-data", "Cursor compiled code cache", "/CachedData", "Generated compilation data", cache},
			{"gpu-cache", "Cursor GPU cache", "/GPUCache", "Generated graphics data", cache},
			{"other", "Cursor settings & work", "", "Settings, databases and recovery data; excludes listed caches", other},
		},
		grok = {
			{"cache", "Download cache", "/cache", "Rebuildable downloads; quit the tool before clearing", cache},
			{"other", "Root metadata & hidden files", "", "Residual after individually measured children; never treated as cache", other},
		},
	}
	local specs = assert(catalogs[id], "Unknown AI tool layout: " .. tostring(id))
	local children = {}
	for _, spec in ipairs(specs) do
		local row = item(id .. "-" .. spec[1], spec[2], spec[4], root .. spec[3], spec[5])
		row.agent = id
		-- Worktrees are reviewed one by one on their own page, never as a folder total.
		if spec[1] == "worktrees" then row.page = "worktrees" end
		table.insert(children, row)
	end
	return group(id, name, "Paths and data types; sessions and worktrees require review", "terminal", "systemPurple", children)
end
return {item = item, group = group, generated = generated, cache = cache, ownerCache = ownerCache, system = system, essential = essential,
	assets = assets, tool = tool, with = with}
