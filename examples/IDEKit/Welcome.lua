local ns = require("AppKit")
local Recent = require("examples.IDEKit.Recent")

local function actionButton(item)
	return ns.Button {
		title = item.title,
		subtitle = item.subtitle,
		systemImage = item.systemImage,
		style = item.style or "plain",
		fixedWidth = item.width or 240,
		fixedHeight = item.height or 56,
		action = item.action,
	}
end

local function Welcome(props)
	props = props or {}
	local recentFolders = props.recentFolders or {}
	local recentFiles = props.recentFiles or {}

	local actionItems = {
		{
			title = "Open Folder…",
			subtitle = "Choose a workspace folder",
			systemImage = "folder",
			style = "primary",
			height = 64,
			action = props.onOpenFolder,
		},
		{
			title = "Open File…",
			subtitle = "Choose a single Lua file",
			systemImage = "doc.text",
			style = "plain",
			height = 56,
			action = props.onOpenFile,
		},
		{
			title = "Open Example Project",
			subtitle = "Load the sample workspace",
			systemImage = "play.rectangle",
			style = "plain",
			height = 56,
			action = props.onOpenExample,
		},
	}

	return ns.HStack {
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
					return actionButton(item)
				end),
			},
			ns.Spacer(),
		},
		ns.Divider { orientation = "vertical" },
		ns.VStack {
			flexGrow = 1,
			spacing = 0,
			alignment = "leading",
			Recent.section("RECENT FOLDERS", "No recent folders yet", recentFolders, props.onOpenRecent),
			ns.Divider(),
			Recent.section("RECENT FILES", "No recent files yet", recentFiles, props.onOpenRecent),
		},
	}
end

return Welcome
