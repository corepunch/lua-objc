local bridge = require("bridge")
local ns = require("AppKit")

-- evalIntoCanvas: evaluate Lua code and render the result into a canvas view.
-- ns.Window is intercepted so scripts that call ns.Window{} render inline.
-- If the script defines a toolbar, buttons are placed in the PreviewArea
-- ControlBar via rebuildToolbar.
local function evalIntoCanvas(canvas, code, rebuildToolbar)
	if not canvas then return end

	local result, err = bridge._eval(code, true)
	bridge._clearContainer(canvas)
	if rebuildToolbar then rebuildToolbar(nil) end

	if err then
		local label = bridge._create("NSTextField")
		label.stringValue = err
		label.bezeled = false
		label.drawsBackground = false
		label.editable = false
		label.textColor = bridge._systemColor("secondary")
		bridge._perform(label, "sizeToFit")
		bridge._add(canvas, label)
	elseif result then
		local toolbarItems = bridge._canvas_toolbar_items(result)
		if rebuildToolbar then rebuildToolbar(toolbarItems) end
		bridge._add(canvas, result)
	end

	bridge._layout(canvas)
end

-- Canvas: the inline preview host view.
-- The canvas itself is a plain VStack that receives the result of evalIntoCanvas.
-- This matches Xcode's macOS preview architecture: content-only, no window chrome.
local function Canvas()
	return ns.VStack {
		flexGrow = 1,
	}
end

return {
	Canvas = Canvas,
	evalIntoCanvas = evalIntoCanvas,
}
