-- Minimal preview example.
-- Run with:  ./lua-objc --preview [--width=400] [--height=300] [--out=out.png] examples/preview.lua

return ns.VStack {
	padding = 24,
	alignment = "leading",
	spacing = 12,
	ns.Title "Hello, Preview",
	ns.Text {
		"This view was rendered offscreen — no NSWindow, no event loop.",
		size = 13,
		color = "secondary",
	},
	ns.Button {
		title = "A Button",
	},
}
