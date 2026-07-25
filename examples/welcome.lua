local ui = require("luaui")

ui.Window {
	title = "Welcome to lua-objc",
	width = 520,
	height = 500,
	transparent_titlebar = true,
	ui.VStack {
		padding = 24,
		alignment = "leading",
		ui.Title "Welcome to lua-objc",
		ui.Text { "Build native AppKit interfaces with a SwiftUI-like Lua API.", size = 13 },
		ui.Text { "Examples", size = 13, weight = "semibold" },
		ui.List {
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
			}
		},
		ui.Toggle { label = "Show this window on launch", is_on = true },
	}
}
