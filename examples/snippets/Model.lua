local Model = {}

Model.groups = {
	{ id = "all", name = "All snippets", icon = "folder" },
	{ id = "ui", name = "UI", icon = "app.badge" },
	{ id = "data", name = "Data", icon = "chart.line.uptrend.xyaxis" },
	{ id = "network", name = "Network", icon = "network" },
	{ id = "productivity", name = "Productivity", icon = "wand.and.stars" },
}

Model.snippets = {
	{
		id = "primary-button",
		title = "Primary button",
		group = "ui",
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
		group = "ui",
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
		group = "ui",
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
		group = "network",
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
		group = "data",
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
		group = "productivity",
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
		group = "productivity",
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
}

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
	for _, snippet in ipairs(Model.snippets) do
		counts.all = (counts.all or 0) + 1
		counts[snippet.group] = (counts[snippet.group] or 0) + 1
	end
	return counts
end

function Model.filteredSnippets(groupId, query)
	local q = (query or ""):lower()
	local results = {}
	for _, snippet in ipairs(Model.snippets) do
		local matchesGroup = groupId == "all" or snippet.group == groupId
		local text = (snippet.title .. " " .. snippet.summary .. " " .. table.concat(snippet.tags, " ")):lower()
		local matchesQuery = q == "" or text:find(q, 1, true) ~= nil
		if matchesGroup and matchesQuery then
			results[#results + 1] = snippet
		end
	end
	return results
end

return Model
