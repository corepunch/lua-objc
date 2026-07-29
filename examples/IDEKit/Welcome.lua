local ns = require("AppKit")
local Recent = require("examples.IDEKit.Recent")

local function actionButton(item, handler)
	return ns.Button {
		title = item.title,
		subtitle = item.subtitle,
		systemImage = item.systemImage,
		style = item.style or "plain",
		fixedWidth = item.width or 240,
		fixedHeight = item.height or 56,
		action = function()
			if handler then
				handler(item)
			end
		end,
	}
end

return function(props)
	props = props or {}
	local recentFolders = props.recentFolders or {}
	local recentFiles = props.recentFiles or {}
	local openFolder = props.onOpenFolder
	local openFile = props.onOpenFile
	local openExample = props.onOpenExample
	local openRecent = props.onOpenRecent

	local actionItems = {
		{
			title = "Open Folder…",
			subtitle = "Choose a workspace folder",
			systemImage = "folder",
			style = "primary",
			height = 64,
			action = openFolder,
		},
		{
			title = "Open File…",
			subtitle = "Choose a single Lua file",
			systemImage = "doc.text",
			style = "plain",
			height = 56,
			action = openFile,
		},
		{
			title = "Open Example Project",
			subtitle = "Load the sample workspace",
			systemImage = "play.rectangle",
			style = "plain",
			height = 56,
			action = openExample,
		},
	}

	return ns.Window {
		title = props.title or "lua-objc IDE",
		width = 860,
		height = 520,
		minWidth = 760,
		minHeight = 480,
		ns.HStack {
			flexGrow = 1,
			spacing = 0,
			alignment = "center",
			ns.VStack {
				fixedWidth = 320,
				paddingHorizontal = 36,
				spacing = 0,
				alignment = "leading",
				ns.Spacer(),
				ns.VStack {
					fixedWidth = 228,
					flexGrow = 0,
					spacing = 10,
					alignment = "leading",
					ns.SystemImage {
						"rectangle.on.rectangle.angled",
						size = 56,
						weight = "regular",
						color = "accent",
						fixedWidth = 56,
						fixedHeight = 56,
						accessibilityLabel = "lua-objc IDE",
					},
					ns.VStack {
						flexGrow = 0,
						spacing = 2,
						alignment = "leading",
						ns.Text { "lua-objc IDE", size = 22, weight = "bold" },
						ns.Text {
							"Open a folder or resume recent work",
							size = 13,
							color = "secondary",
						},
					},
				},
				ns.Spacer { fixedHeight = 32 },
				ns.VStack {
					fixedWidth = 228,
					flexGrow = 0,
					spacing = 8,
					alignment = "leading",
					ns.ForEach(actionItems, function(item)
						return actionButton(item, item.action)
					end),
				},
				ns.Spacer(),
			},
			ns.Divider { orientation = "vertical" },
			ns.VStack {
				flexGrow = 1,
				spacing = 0,
				alignment = "leading",
				Recent.section("RECENT FOLDERS", "No recent folders yet", recentFolders, openRecent),
				ns.Divider(),
				Recent.section("RECENT FILES", "No recent files yet", recentFiles, openRecent),
			},
		},
	}
end
