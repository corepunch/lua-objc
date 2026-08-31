local Model = {}

Model.state = {
	favorites = {},
	recents = {},
	selectedFolder = "all",
	selectedSnippetId = nil,
}

Model.groups = {
	{ id = "all", name = "All snippets", icon = "folder" },
	{ id = "favorites", name = "Favorites", icon = "star.fill" },
	{ id = "recent", name = "Recent", icon = "clock" },
	{ id = "ui", name = "UI", icon = "app.badge" },
	{ id = "data", name = "Data", icon = "chart.line.uptrend.xyaxis" },
	{ id = "network", name = "Network", icon = "network" },
	{ id = "productivity", name = "Productivity", icon = "wand.and.stars" },
}

local DEFAULT_SNIPPETS = {
	{
		id = "primary-button",
		title = "Primary button",
		folder = "ui",
		language = "lua",
		favorite = true,
		summary = "Call-to-action style for a Save or Continue flow.",
		tags = { "button", "primary", "action" },
		code = [[local ns = require("AppKit")

return ns.Button {
	title = "Save",
	style = "primary",
	action = function()
	print("Saved")
end,
}]],
	},
	{
		id = "search-field",
		title = "Search field",
		folder = "ui",
		language = "lua",
		favorite = false,
		summary = "A filter control with live text updates.",
		tags = { "search", "filter", "input" },
		code = [[local ns = require("AppKit")

return ns.SearchField {
	placeholder = "Search snippets",
	accessibilityLabel = "Search snippets",
	onChange = function(value)
	print("query:", value)
end,
}]],
	},
	{
		id = "list-row",
		title = "List row",
		folder = "ui",
		language = "lua",
		favorite = true,
		summary = "A compact row layout for source lists or tool palettes.",
		tags = { "list", "row", "table" },
		code = [[local ns = require("AppKit")

return ns.List {
	style = "plain",
	header = false,
	rowHeight = 48,
	columns = {
		{ id = "name", title = "Name" },
		{ id = "updated", title = "Updated", width = 110 },
	},
}]],
	},
	{
		id = "fetch-json",
		title = "Fetch JSON",
		folder = "network",
		language = "lua",
		favorite = false,
		summary = "Load remote payloads asynchronously with AppKit scheduling.",
		tags = { "network", "json", "async" },
		code = [[local ns = require("AppKit")

ns.async(function()
	local body = "{\"status\": \"ok\"}"
	local ok, data = pcall(function()
		return JSON.parse(body)
	end)
	if ok then
		print(data.status)
	end
end)]],
	},
	{
		id = "group-by-tag",
		title = "Group by tag",
		folder = "data",
		language = "lua",
		favorite = false,
		summary = "Group snippets by tag for quick browsing.",
		tags = { "tags", "grouping", "index" },
		code = [[local tags = {}
for _, item in ipairs(items) do
	for _, tag in ipairs(item.tags or {}) do
		tags[tag] = tags[tag] or {}
		tags[tag][#tags[tag] + 1] = item
	end
end

return tags]],
	},
	{
		id = "time-formatter",
		title = "Time formatter",
		folder = "productivity",
		language = "lua",
		favorite = true,
		summary = "Turn timestamps into concise human-readable strings.",
		tags = { "time", "format", "utility" },
		code = [[local function formatTime(ts)
	local diff = os.difftime(os.time(), ts)
	if diff < 60 then
		return "just now"
	elseif diff < 3600 then
		return string.format("%.0f minutes ago", diff / 60)
	end
	return os.date("%Y-%m-%d", ts)
end]],
	},
	{
		id = "text-editor",
		title = "Code editor",
		folder = "productivity",
		language = "lua",
		favorite = false,
		summary = "A native editable text surface for snippets and docs.",
		tags = { "editor", "code", "text" },
		code = [[local ns = require("AppKit")

return ns.TextEditor {
	language = "lua",
	text = "-- edit me",
	wrapMode = false,
	flexGrow = 1,
}]],
	},
	{
		id = "json-filter",
		title = "JSON filter",
		folder = "data",
		language = "json",
		favorite = false,
		summary = "Filter a list of records by field and category.",
		tags = { "json", "filter", "records" },
		code = [[{
	"status": "ok",
	"items": [
		{"id": 1, "category": "ui", "label": "Button"},
		{"id": 2, "category": "network", "label": "Fetch"}
	]
}]],
	},
}

function Model.statePath()
	local home = os.getenv("HOME") or "."
	return home .. "/Library/Application Support/lua-objc/snippets_state.lua"
end

function Model.loadState()
	local path = Model.statePath()
	local loaded = {
		favorites = {},
		recents = {},
		selectedFolder = "all",
		selectedSnippetId = nil,
	}
	local file = io.open(path, "r")
	if not file then return loaded end
	local body = file:read("*a")
	file:close()
	if not body or body == "" then return loaded end
	local ok, data = pcall(function()
		local chunk = assert(load(body, "@snippets_state"))
		return chunk()
	end)
	if not ok or type(data) ~= "table" then return loaded end
	if type(data.favorites) == "table" then loaded.favorites = data.favorites end
	if type(data.recents) == "table" then loaded.recents = data.recents end
	if type(data.selectedFolder) == "string" then loaded.selectedFolder = data.selectedFolder end
	if type(data.selectedSnippetId) == "string" then loaded.selectedSnippetId = data.selectedSnippetId end
	return loaded
end

function Model.saveState()
	local path = Model.statePath()
	local dir = path:match("^(.-)[^/\\]+$")
	if dir and dir ~= "" then
		os.execute("mkdir -p " .. string.format("%q", dir))
	end
	local file = io.open(path, "w")
	if not file then return false end
	local lines = {
		"return {",
		"  favorites = {",
	}
	local favorites = {}
	for id, enabled in pairs(Model.state.favorites) do
		if enabled then favorites[#favorites + 1] = id end
	end
	table.sort(favorites)
	for i, id in ipairs(favorites) do
		lines[#lines + 1] = string.format("    [%q] = true%s", id, i == #favorites and "" or ",")
	end
	lines[#lines + 1] = "  },"
	lines[#lines + 1] = "  recents = {"
	for i, id in ipairs(Model.state.recents or {}) do
		lines[#lines + 1] = string.format("    [%d] = %q%s", i, id, i == #Model.state.recents and "" or ",")
	end
	lines[#lines + 1] = "  },"
	lines[#lines + 1] = string.format("  selectedFolder = %q,", Model.state.selectedFolder or "all")
	if Model.state.selectedSnippetId then
		lines[#lines + 1] = string.format("  selectedSnippetId = %q,", Model.state.selectedSnippetId)
	end
	lines[#lines + 1] = "}"
	file:write(table.concat(lines, "\n"))
	file:close()
	return true
end

function Model.initialize()
	Model.state = Model.loadState()
	Model.state.favorites = Model.state.favorites or {}
	Model.state.recents = Model.state.recents or {}
	if not Model.snippets or #Model.snippets == 0 then
		Model.snippets = {}
		for _, snippet in ipairs(DEFAULT_SNIPPETS) do
			local copy = {}
			for key, value in pairs(snippet) do copy[key] = value end
			copy.favorite = Model.state.favorites[copy.id] == true or copy.favorite == true
			Model.state.favorites[copy.id] = copy.favorite and true or false
			Model.snippets[#Model.snippets + 1] = copy
		end
	end
	for _, snippet in ipairs(Model.snippets) do
		snippet.favorite = Model.state.favorites[snippet.id] == true or snippet.favorite == true
		Model.state.favorites[snippet.id] = snippet.favorite and true or false
		snippet.tags = snippet.tags or {}
		snippet.folder = snippet.folder or "productivity"
		snippet.language = snippet.language or "lua"
	end
	return Model.snippets
end

function Model.findById(id)
	for _, snippet in ipairs(Model.snippets) do
		if snippet.id == id then
			return snippet
		end
	end
	return nil
end

function Model.groupCounts()
	local counts = {}
	for _, group in ipairs(Model.groups) do
		counts[group.id] = 0
	end
	counts.all = 0
	counts.favorites = 0
	counts.recent = #Model.state.recents
	for _, snippet in ipairs(Model.snippets) do
		counts.all = counts.all + 1
		if snippet.favorite then counts.favorites = counts.favorites + 1 end
		counts[snippet.folder] = (counts[snippet.folder] or 0) + 1
	end
	return counts
end

function Model.folderRows()
	local counts = Model.groupCounts()
	local rows = {}
	for _, group in ipairs(Model.groups) do
		rows[#rows + 1] = {
			_id = group.id,
			name = group.name,
			count = tostring(counts[group.id] or 0),
			icon = group.icon,
		}
	end
	return rows
end

function Model.tagRows(folderId)
	local tags = {}
	local index = {}
	for _, snippet in ipairs(Model.snippets) do
		local matchesFolder = folderId == "all" or folderId == "favorites" and snippet.favorite or folderId == "recent" and Model.isRecent(snippet.id) or snippet.folder == folderId
		if matchesFolder then
			for _, tag in ipairs(snippet.tags or {}) do
				local key = tag:lower()
				if not index[key] then
					index[key] = true
					tags[#tags + 1] = { _id = key, name = tag }
				end
			end
		end
	end
	table.sort(tags, function(a, b) return a.name < b.name end)
	return tags
end

function Model.isRecent(id)
	for _, recentId in ipairs(Model.state.recents or {}) do
		if recentId == id then return true end
	end
	return false
end

function Model.recentSnippets()
	local items = {}
	for _, id in ipairs(Model.state.recents or {}) do
		items[#items + 1] = id
	end
	return items
end

function Model.recordRecent(id)
	if not id or id == "" then return end
	local seen = {}
	local recent = {}
	for _, current in ipairs(Model.state.recents or {}) do
		if current ~= id and not seen[current] then
			seen[current] = true
			recent[#recent + 1] = current
		end
	end
	recent[#recent + 1] = id
	if #recent > 12 then
		table.remove(recent, 1)
	end
	Model.state.recents = recent
	Model.saveState()
end

function Model.toggleFavorite(id)
	if not id then return false end
	local snippet = Model.findById(id)
	if not snippet then return false end
	snippet.favorite = not snippet.favorite
	Model.state.favorites[id] = snippet.favorite and true or false
	Model.saveState()
	return snippet.favorite
end

function Model.isFavorite(id)
	if not id then return false end
	if Model.snippets then
		local snippet = Model.findById(id)
		if snippet and snippet.favorite ~= nil then
			return snippet.favorite
		end
	end
	return Model.state.favorites[id] == true or false
end

function Model.filterSnippets(folderId, query, favoritesOnly, recentOnly)
	local q = (query or ""):lower()
	local results = {}
	for _, snippet in ipairs(Model.snippets) do
		local matchesFolder = true
		if folderId == "all" then
			matchesFolder = true
		elseif folderId == "favorites" then
			matchesFolder = snippet.favorite
		elseif folderId == "recent" then
			matchesFolder = Model.isRecent(snippet.id)
		else
			matchesFolder = snippet.folder == folderId
		end
		if favoritesOnly and not snippet.favorite then
			matchesFolder = false
		end
		if recentOnly and not Model.isRecent(snippet.id) then
			matchesFolder = false
		end
		local text = ((snippet.title or "") .. " " .. (snippet.summary or "") .. " " .. (table.concat(snippet.tags or {}, " ")) .. " " .. (snippet.code or "")):lower()
		local matchesQuery = q == "" or text:find(q, 1, true) ~= nil
		if matchesFolder and matchesQuery then
			results[#results + 1] = snippet
		end
	end
	if recentOnly then
		local index = {}
		for _, id in ipairs(Model.state.recents or {}) do index[id] = true end
		local ordered = {}
		for _, id in ipairs(Model.state.recents or {}) do
			for _, snippet in ipairs(results) do
				if snippet.id == id then
					ordered[#ordered + 1] = snippet
					break
				end
			end
		end
		return ordered
	end
	return results
end

function Model.languageForName(name)
	if type(name) ~= "string" then return "text" end
	local lower = name:lower()
	if lower:find("lua") then return "lua" end
	if lower:find("javascript") or lower:find("js") then return "javascript" end
	if lower:find("python") or lower:find("py") then return "python" end
	if lower:find("json") then return "json" end
	if lower:find("markdown") or lower:find("md") then return "markdown" end
	if lower:find("shell") or lower:find("bash") then return "shell" end
	if lower:find("swift") then return "swift" end
	if lower:find("css") then return "css" end
	if lower:find("html") then return "html" end
	return "text"
end

function Model.executeSnippet(snippet)
	if not snippet then return "", "No snippet selected." end
	local code = snippet.code or ""
	if code == "" then return "", "Snippet is empty." end
	local output = {}
	local env = {
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[#parts + 1] = tostring(select(i, ...))
			end
			output[#output + 1] = table.concat(parts, "\t")
		end,
		math = math,
		table = table,
		string = string,
		tonumber = tonumber,
		tostring = tostring,
		pairs = pairs,
		ipairs = ipairs,
		os = {
			time = os.time,
			difftime = os.difftime,
			date = os.date,
		},
		require = require,
	}
	local fn, err = load(code, "snippet:" .. (snippet.id or "snippet"), "t", env)
	if not fn then return "", "Syntax error: " .. tostring(err) end
	local ok, result = pcall(fn)
	if not ok then
		local message = tostring(result)
		return table.concat(output, "\n"), "Runtime error: " .. message
	end
	if result ~= nil then
		output[#output + 1] = tostring(result)
	end
	local body = table.concat(output, "\n")
	if body == "" then
		return "Snippet ran without output.", nil
	end
	return body, nil
end

Model.initialize()

return Model
