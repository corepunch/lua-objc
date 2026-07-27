-- Editor: code-editor view backed by NSTextView.
-- The actual editor behavior lives in Plugins/TextEditor.lua; this wrapper
-- keeps the IDE canvas debounce and preserves the historical IDEKit.Editor API.
local bridge = require("bridge")
local canvasMod = require("examples.ide.components.canvas")

local function Editor(props)
	props = props or {}
	local canvas = props.canvas
	local eval_version = 0

	local plugin = props.plugin
	if not plugin or type(plugin.create) ~= "function" then
		error("Editor requires props.plugin")
	end
	local editor = plugin.create {
		initialCode = props.initialCode,
		language = props.language or "lua",
	}

	if canvas then
		editor:setChangeHandler(function(text)
			eval_version = eval_version + 1
			local version = eval_version
			bridge._timerAfter(0.3, function()
				if version ~= eval_version then return end
				canvasMod.evalIntoCanvas(canvas, text)
			end)
		end)
	end

	if canvas and props.initialCode then
		canvasMod.evalIntoCanvas(canvas, props.initialCode)
	end

	return editor
end

return Editor
