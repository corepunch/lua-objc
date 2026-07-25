local ui = require("luaui")

ui.Window {
	title = "Lua + ObjC Demo",
	width = 480,
	height = 420,
	ui.VStack {
		padding = 24,
		alignment = "leading",
		ui.Title "Hello from Lua",
		ui.Text "A SwiftUI-like API backed by native AppKit controls.",
		ui.Image "/Library/Desktop Pictures/Beach.jpg",
		ui.Text "Edit the Lua file and relaunch—no recompilation needed.",
	},
}
