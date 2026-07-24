local ui = require("luaui")

ui.Window {
	title = "Welcome to lua-objc",
	width = 520,
	height = 500,
	transparent_titlebar = true,
	ui.VStack {
		ui.Spacer(),
		ui.HStack { ui.Spacer(), ui.Title "Welcome to lua-objc", ui.Spacer() },
		ui.HStack { ui.Spacer(), ui.Text { "A Lua to AppKit UI framework", size = 13 }, ui.Spacer() },
		ui.Spacer(),
		ui.Button { title = "Create New Script" },
		ui.Button { title = "Open Existing Example" },
		ui.Button { title = "Clone Repository" },
		ui.Separator(),
		ui.Text { "Recent", size = 11, weight = "semibold" },
		ui.List {
			width = 480,
			height = 150,
			columns = {
				{ id = "name", title = "Name" },
				{ id = "time", title = "Opened" },
			},
			data = {
				{ name = "hello.lua",   time = "just now" },
				{ name = "list.lua",    time = "8 min ago" },
				{ name = "live.lua",    time = "12 min ago" },
				{ name = "weather.lua", time = "20 min ago" },
			}
		},
		ui.Separator(),
		ui.Toggle { label = "Show this window on launch", is_on = true },
		ui.Spacer(),
	}
}
