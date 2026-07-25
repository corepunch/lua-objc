local ns = require("AppKit")

ns.Window {
	title = "Lua + ObjC Demo",
	width = 480,
	height = 420,
	ns.VStack {
		padding = 24,
		alignment = "leading",
		ns.Title "Hello from Lua",
		ns.Text "A SwiftUI-like API backed by native AppKit controls.",
		ns.Image "/Library/Desktop Pictures/Beach.jpg",
		ns.Text "Edit the Lua file and relaunch—no recompilation needed.",
	},
}
