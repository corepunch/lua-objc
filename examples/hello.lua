local ui = require("luaui")

ui.Window {
	title = "Lua + ObjC Demo",
	width = 480,
	height = 420,

	ui.Text "Hello from Lua!",
	ui.Text "This is a SwiftUI-like API",
	ui.Text "running on AppKit via Lua C bridge.",

	ui.Image "/Library/Desktop Pictures/Beach.jpg",

	ui.Text "No recompilation needed —",
	ui.Text "just edit the .lua file and re-run.",
}
