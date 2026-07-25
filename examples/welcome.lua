local ns = require("AppKit")

ns.Window {
	title = "Welcome to lua-objc",
	width = 520,
	height = 500,
	transparentTitlebar = true,
	ns.VStack {
		padding = 24,
		alignment = "leading",
		ns.Title "Welcome to lua-objc",
		ns.Text { "Build native AppKit interfaces with a SwiftUI-like Lua API.", size = 13 },
		ns.Text { "Examples", size = 13, weight = "semibold" },
		ns.List {
			width = 472,
			height = 320,
			columns = {
				{ id = "name", title = "Name" },
				{ id = "purpose", title = "Demonstrates" },
			},
			data = {
				{ name = "hello.lua",   purpose = "Text, images, and stacks" },
				{ name = "list.lua",    purpose = "Native tables" },
				{ name = "live.lua",    purpose = "Async updates and toolbars" },
				{ name = "weather.lua", purpose = "Network data and progress" },
				{ name = "mail.lua",    purpose = "Split views and sidebars" },
				{ name = "layout.lua",  purpose = "Measured flexible layout" },
			}
		},
		ns.Toggle { label = "Show this window on launch", is_on = true },
	}
}
