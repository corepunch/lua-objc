local bridge = require("AppKitNative")
local ns = require("AppKit")

local function evalIntoCanvas(canvas, code, previewArea)
	if not canvas then return end

	local result, err = bridge._eval(code, true)
	canvas:clearContainer()

	if err then
		local label = bridge._textField()
		label.text = err
		label.bezeled = false
		label.drawsBackground = false
		label.editable = false
		label.textColor = bridge._systemColor("secondary")
		label:sizeToFit()
		canvas:add(label)
		if previewArea then previewArea:setContent(nil, nil) end
	elseif result then
		local toolbarItems = bridge._canvas_toolbar_items(result)
		canvas:add(result)
		if previewArea then previewArea:setContent(result, toolbarItems) end
	end

	canvas:layout()
end

local function Canvas()
	return ns.VStack {
		flexGrow = 1,
	}
end

return {
	Canvas = Canvas,
	evalIntoCanvas = evalIntoCanvas,
}
