-- The application menu bar, modelled on SwiftUI's `.commands`. The standard
-- macOS menus (app, File, Edit, View, Window, Help) are built from named
-- command groups; an app replaces, precedes or follows a group with
-- `CommandGroup` records and adds its own top-level menus with `CommandMenu`,
-- which sit between View and Window as in SwiftUI and the HIG.
--
-- Items are plain records: `{title, action | selector | role, keyEquivalent,
-- modifiers, tag, systemImage, checked, disabled, validate, items}` or
-- `{separator = true}`. `selector` sends a standard AppKit action through the
-- responder chain, so AppKit validates and titles it (Show/Hide Sidebar,
-- Undo, Close). This module only assembles data; the platform installs it.
local commands = {}

local function item(title, selector, key, modifiers, tag)
	return {title = title, selector = selector, keyEquivalent = key or "", modifiers = modifiers, tag = tag}
end

-- NSTextFinderAction values for performFindPanelAction: items.
local FIND = {show = 1, next = 2, previous = 3, useSelection = 7}

-- Placement names follow SwiftUI's CommandGroupPlacement.
commands.placements = {
	"appInfo", "appSettings", "systemServices", "appVisibility", "appTermination",
	"newItem", "saveItem", "importExport", "printItem",
	"undoRedo", "pasteboard", "textEditing",
	"toolbar", "sidebar", "fullScreen",
	"windowSize", "windowArrangement",
	"help",
}

local function defaultGroups(appName)
	return {
		appInfo = {{title = "About " .. appName, role = "about"}},
		appSettings = {},
		systemServices = {{title = "Services", role = "services"}},
		appVisibility = {
			item("Hide " .. appName, "hide:", "h"),
			item("Hide Others", "hideOtherApplications:", "h", "command,option"),
			item("Show All", "unhideAllApplications:"),
		},
		appTermination = {item("Quit " .. appName, "terminate:", "q")},
		newItem = {},
		saveItem = {item("Close", "performClose:", "w")},
		importExport = {},
		printItem = {},
		undoRedo = {item("Undo", "undo:", "z"), item("Redo", "redo:", "z", "command,shift")},
		pasteboard = {
			item("Cut", "cut:", "x"), item("Copy", "copy:", "c"), item("Paste", "paste:", "v"),
			item("Paste and Match Style", "pasteAsPlainText:", "v", "command,option,shift"),
			item("Delete", "delete:"), item("Select All", "selectAll:", "a"),
		},
		-- NSTextFinder actions carry their operation in the item's tag; the
		-- responder chain routes performFindPanelAction: to text views.
		textEditing = {{title = "Find", items = {
			item("Find…", "performFindPanelAction:", "f", nil, FIND.show),
			item("Find Next", "performFindPanelAction:", "g", nil, FIND.next),
			item("Find Previous", "performFindPanelAction:", "g", "command,shift", FIND.previous),
			item("Use Selection for Find", "performFindPanelAction:", "e", nil, FIND.useSelection),
		}}},
		toolbar = {
			item("Show Toolbar", "toggleToolbarShown:", "t", "command,option"),
			item("Customize Toolbar…", "runToolbarCustomizationPalette:"),
		},
		sidebar = {item("Show Sidebar", "toggleSidebar:", "s", "command,control")},
		fullScreen = {item("Enter Full Screen", "toggleFullScreen:", "f", "command,control")},
		windowSize = {item("Minimize", "performMiniaturize:", "m"), item("Zoom", "performZoom:")},
		windowArrangement = {item("Bring All to Front", "arrangeInFront:")},
		help = {item(appName .. " Help", "showHelp:", "?")},
	}
end

-- Standard menus as ordered group lists; groups are separated by dividers.
local LAYOUT = {
	{title = "@app", groups = {"appInfo", "appSettings", "systemServices", "appVisibility", "appTermination"}},
	{title = "File", groups = {"newItem", "saveItem", "importExport", "printItem"}},
	{title = "Edit", groups = {"undoRedo", "pasteboard", "textEditing"}},
	{title = "View", groups = {"toolbar", "sidebar", "fullScreen"}},
	{title = "Window", role = "windows", groups = {"windowSize", "windowArrangement"}},
	{title = "Help", role = "help", groups = {"help"}},
}

local function isPlacement(name)
	for _, placement in ipairs(commands.placements) do
		if placement == name then return true end
	end
	return false
end

-- Joins non-empty groups with single separators and drops separators at
-- either end, so an emptied group never leaves a double divider.
local function join(groups)
	local items = {}
	for _, group in ipairs(groups) do
		if #group > 0 then
			if #items > 0 then table.insert(items, {separator = true}) end
			for _, value in ipairs(group) do table.insert(items, value) end
		end
	end
	return items
end

-- Title-cases an entry folder name: "adventure-arena" → "Adventure Arena".
function commands.displayName(name)
	return (name:gsub("[-_]+", " "):gsub("(%a)([%w']*)", function(first, rest)
		return first:upper() .. rest
	end))
end

-- The app's name: the declared one, else the entry point's folder
-- (`apps/diskmap/init.lua` → "Diskmap") or file name.
function commands.appName(declared, entry)
	if declared and declared ~= "" then return declared end
	entry = entry or (_G.arg and _G.arg[0]) or ""
	local folder = entry:match("([^/]+)/init%.lua$")
	local name = folder or entry:match("([^/]+)%.lua$") or entry:match("([^/]+)/?$")
	if not name or name == "" then return "lua-objc" end
	return commands.displayName(name)
end

-- Builds `{appName, menus, helpTopics}` from a `<Commands>` spec:
-- `{appName, groups = {{placement, position, items}}, menus = {{title, items}},
-- helpTopics = {{title, keywords, action}}}`. `position` is "replacing",
-- "before" or "after".
function commands.build(spec)
	spec = spec or {}
	local appName = commands.appName(spec.appName)
	local groups = defaultGroups(appName)
	local before, after = {}, {}
	for _, group in ipairs(spec.groups or {}) do
		local placement = group.placement
		if not isPlacement(placement) then
			error("commands: unknown CommandGroup placement \"" .. tostring(placement) .. "\"")
		end
		local position = group.position or "replacing"
		if position == "replacing" then
			groups[placement] = group.items or {}
		elseif position == "before" or position == "after" then
			local target = position == "before" and before or after
			target[placement] = target[placement] or {}
			table.insert(target[placement], group.items or {})
		else
			error("commands: CommandGroup position must be replacing, before or after")
		end
	end

	local menus = {}
	local function addStandard(layout)
		local ordered = {}
		for _, name in ipairs(layout.groups) do
			for _, extra in ipairs(before[name] or {}) do table.insert(ordered, extra) end
			table.insert(ordered, groups[name])
			for _, extra in ipairs(after[name] or {}) do table.insert(ordered, extra) end
		end
		local items = join(ordered)
		-- The app, Window and Help menus always exist; File, Edit and View
		-- only when something is left in them.
		if #items > 0 or layout.role or layout.title == "@app" then
			table.insert(menus, {title = layout.title == "@app" and appName or layout.title,
				role = layout.role, items = items})
		end
	end
	for _, layout in ipairs(LAYOUT) do
		if layout.title == "Window" then
			for _, menu in ipairs(spec.menus or {}) do
				table.insert(menus, {title = menu.title, items = menu.items or {}})
			end
		end
		addStandard(layout)
	end
	return {appName = appName, menus = menus, helpTopics = spec.helpTopics}
end

return commands
