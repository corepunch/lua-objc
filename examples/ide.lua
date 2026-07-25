local ns = require("AppKit")
local ide = require("IDEKit")

local canvas = ide.Canvas()
local editor = ide.Editor {
	canvas = canvas,
	initialCode = [=[
-- Try changing the text and see it update in the canvas
return ns.VStack {
	padding = 16,
	alignment = "leading",
	ns.Title "Hello, lua-objc",
	ns.Text {
		"Edit the code in the center. The canvas updates as you type.",
		size = 13,
		color = "secondary",
	},
	ns.Spacer(),
	ns.Button {
		title = "A Button",
		action = function() print("clicked") end,
	},
}
]=],
}

local files = {
	{ name = "hello.lua" },
	{ name = "list.lua" },
	{ name = "live.lua" },
	{ name = "weather.lua" },
	{ name = "mail.lua" },
	{ name = "welcome.lua" },
}

local fileTree = ns.List {
	header = false,
	bordered = true,
	flexGrow = 1,
	columns = {
		{
			id = "name",
			title = "Name",
			systemImage = "doc.text",
		},
	},
	data = files,
}

local function Panel(title, content, props)
	props = props or {}
	return ns.VStack {
		fixedWidth = props.fixedWidth,
		flexGrow = props.flexGrow,
		spacing = 0,
		ns.HStack {
			fixedHeight = 28,
			paddingHorizontal = 10,
			alignment = "center",
			ns.Text {
				title,
				size = 11,
				weight = "semibold",
				color = "secondary",
			},
		},
		content,
	}
end

ns.Window {
	title = "lua-objc IDE",
	width = 1100,
	height = 680,
	minWidth = 800,
	minHeight = 500,

	ns.VStack {
		flexGrow = 1,
		spacing = 0,
		ns.HSplit {
			flexGrow = 1,
			Panel("Files", fileTree, { fixedWidth = 220 }),
			Panel("Editor", editor, { flexGrow = 1 }),
			Panel("Canvas", canvas, { flexGrow = 1 }),
		},
	},
}
