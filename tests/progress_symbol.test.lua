_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

-- SwiftUI's ProgressView() spins once it appears; an indeterminate indicator
-- that hides while stopped must not stay invisible.
local spinner = ns.ProgressView {}
t.expect(not spinner.spinning, "a spinner outside a window is idle")
local window = ns.Window { visible = false, width = 200, height = 100 }
window:add(spinner)
t.expect(spinner.spinning, "an indeterminate spinner animates in a window")
local bar = ns.ProgressView { value = 0.5 }
window:add(bar)
t.expect(not bar.spinning, "determinate progress never spins")

-- A symbol takes its whole glyph, as Image(systemName:) does, rather than
-- NSImageView's cap-height alignment rectangle that shrank square glyphs.
for _, name in ipairs({ "1.circle.fill", "circle.fill", "hand.raised.fill" }) do
	local symbol = ns.SystemImage { name, size = 18, color = "systemBlue" }
	local size, image = symbol.intrinsicContentSize, symbol.image.size
	t.expect(size.width == image.width and size.height == image.height, name .. " is as tall as its glyph")
	t.expect(size.height >= 18, name .. " is at least its point size tall")
end

os.exit(t.summary() and 0 or 1)
