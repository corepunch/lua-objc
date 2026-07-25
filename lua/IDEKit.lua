local ns = require("AppKit")
local bridge = require("bridge")

local IDEKit = {}

function IDEKit.Editor(props)
	props = props or {}
	local canvas = props.canvas
	local editor = bridge._textView()

	if props.initialCode then
		bridge._textViewSetText(editor, props.initialCode)
	end

	local eval_version = 0

	bridge._textViewOnChange(editor, function(text)
		eval_version = eval_version + 1
		local version = eval_version
		bridge._timerAfter(0.3, function()
			if version ~= eval_version then return end
			IDEKit._evalIntoCanvas(canvas, text)
		end)
	end)

	if props.initialCode and canvas then
		IDEKit._evalIntoCanvas(canvas, props.initialCode)
	end

	return editor
end

function IDEKit._evalIntoCanvas(canvas, code)
	if not canvas then return end

	local result, err = bridge._eval(code)
	bridge._clearContainer(canvas)

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
		bridge._add(canvas, result)
	end

	bridge._layout(canvas)
end

function IDEKit.Canvas(props)
	return ns.VStack {
		flexGrow = 1,
	}
end

return IDEKit
