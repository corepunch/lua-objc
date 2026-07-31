local ns = require("AppKit")
local bridge = require("AppKitNative")
local canvasMod = require("examples.IDEKit.Canvas")
local PreviewArea = require("examples.IDEKit.PreviewArea")

local function EditorArea(props)
	props = props or {}

	local canvas = canvasMod.Canvas()
	local previewArea = PreviewArea { canvas = canvas }

	local textView = ns.TextEditor {
		language = props.language or "lua",
		wrapMode = props.wrapMode ~= false,
		flexGrow = 1,
		fillWidth = true,
	}

	local function evaluate(code)
		canvasMod.evalIntoCanvas(canvas, code, previewArea)
	end

	local version = 0
	textView:onChange(function(text)
		version = version + 1
		local snap = version
		bridge._timerAfter(0.3, function()
			if snap == version then evaluate(text) end
		end)
	end)

	local editorPane = ns.VStack {
		flexGrow = 1,
		fillWidth = true,
		spacing = 0,
		textView,
	}

	local previewPane = ns.VStack {
		flexGrow = 1,
		fillWidth = true,
		spacing = 0,
		previewArea.view,
	}

	local split = ns.HSplit {
		flexGrow = 1,
		proportions = props.proportions or { 1, 1 },
		editorPane,
		previewPane,
	}

	local self = {
		view = split,
		textView = textView,
		evaluate = evaluate,
		togglePreview = function()
			previewPane.hidden = not previewPane.hidden
		end,
	}

	return self
end

return EditorArea
