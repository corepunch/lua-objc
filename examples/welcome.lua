local ns = require("AppKit")

local home = os.getenv("HOME") or "~"
local nature_portfolio = home
	.. "/Developer/presenter/demo/Nature Portfolio.slides"

local recent_presentations = {
	{
		title = "Nature Portfolio",
		location = nature_portfolio,
		lastOpened = "38 min ago",
	},
	{
		title = "Nature Portfolio",
		location = nature_portfolio,
		lastOpened = "16 hr ago",
	},
}

local welcome_actions = {
	{
		title = "Create New Presentation",
		subtitle = "Start with a blank canvas",
		systemImage = "plus.rectangle.on.rectangle",
		style = "primary",
		height = 64,
		actionName = "Create New Presentation",
	},
	{
		title = "Open Presentation…",
		subtitle = "Open a .slides file",
		systemImage = "folder",
		style = "plain",
		height = 58,
		actionName = "Open Presentation",
	},
	{
		title = "Open Example Presentation",
		subtitle = "Explore a sample deck",
		systemImage = "play.rectangle",
		style = "plain",
		height = 58,
		actionName = "Open Example Presentation",
	},
}

local function action(title)
	return function()
		print(title)
	end
end

local function welcome_action_button(item)
	return ns.Button {
		title = item.title,
		subtitle = item.subtitle,
		systemImage = item.systemImage,
		style = item.style,
		fixedWidth = 228,
		fixedHeight = item.height,
		action = action(item.actionName),
	}
end

local function recent_presentation_row(presentation)
	return ns.Button {
		title = presentation.title,
		subtitle = presentation.location,
		detail = presentation.lastOpened,
		systemImage = "doc.richtext",
		style = "row",
		fixedHeight = 52,
		fillWidth = true,
		action = action("Open " .. presentation.location),
	}
end

local left_panel = ns.VStack {
	fixedWidth = 300,
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
			accessibilityLabel = "QuickSlides",
		},

		ns.VStack {
			flexGrow = 0,
			spacing = 2,
			alignment = "leading",
			ns.Text { "QuickSlides", size = 22, weight = "bold" },
			ns.Text {
				"Create, review, and present",
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

		ns.ForEach(welcome_actions, welcome_action_button),
	},

	ns.Spacer(),
}

local right_panel = ns.VStack {
	flexGrow = 1,
	spacing = 0,
	alignment = "leading",

	ns.HStack {
		fixedHeight = 43,
		paddingHorizontal = 20,
		alignment = "center",
		ns.Text {
			"RECENT PRESENTATIONS",
			size = 11,
			weight = "semibold",
			color = "secondary",
		},
	},

	ns.Divider(),

	ns.ForEach(recent_presentations, function(presentation, index, count)
		local row = recent_presentation_row(presentation)
		if index == count then
			return row
		end
		return ns.Group {
			row,
			ns.HStack {
				fixedHeight = 1,
				spacing = 0,
				ns.Spacer { fixedWidth = 52 },
				ns.Divider(),
			},
		}
	end),

	ns.Spacer(),
	ns.Divider(),

	ns.Button {
		title = "Open Other…",
		style = "link",
		fixedHeight = 40,
		fillWidth = true,
		action = action("Open Other"),
	},
}

return ns.Window {
	title = "Xcode Previews",
	width = 740,
	height = 440,
	minWidth = 740,
	minHeight = 440,

	ns.HStack {
		flexGrow = 1,
		spacing = 0,
		alignment = "center",
		left_panel,
		ns.Divider { orientation = "vertical" },
		right_panel,
	},
}
