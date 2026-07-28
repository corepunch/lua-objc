local bridge = require("bridge")
local App = require("App")
local TextEditor = {}

local function resumeCoroutine(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		io.stderr:write("coroutine error: " .. tostring(err) .. "\n")
	end
	return ok, err
end

local function createEditor(props)
	props = props or {}

	local view = bridge._textView()
	view:setLanguage(props.language or "lua")

	if props.initialCode then
		view:setText(props.initialCode)
	end

	local editor = {
		_view = view,
		_plugin = TextEditor,
	}

	local changeHandler = nil
	local currentFile = nil

	function editor:setChangeHandler(handler)
		changeHandler = handler
	end

	function editor:setText(text)
		view:setText(text or "")
	end

	function editor:getText()
		return view:getText()
	end

	function editor:setLanguage(language)
		view:setLanguage(language or "lua")
	end

	function editor:setWrapMode(wrapped)
		view:setWrapMode(wrapped and true or false)
	end

	function editor:watchFile(path)
		if currentFile then
			bridge._watchFile(currentFile, nil)
			currentFile = nil
		end

		currentFile = path
		if not path then
			return
		end

		bridge._watchFile(path, function()
			local f = io.open(path, "r")
			if not f then
				return
			end
			local content = f:read("*a")
			f:close()

			view:setText(content)

			if changeHandler then
				local co = coroutine.create(function()
					changeHandler(content, editor)
				end)
				resumeCoroutine(co)
			end
		end)
	end

	function editor:destroy()
		if currentFile then
			bridge._watchFile(currentFile, nil)
			currentFile = nil
		end
	end

	view:onChange(function(text)
		if changeHandler then
			changeHandler(text, editor)
		end
	end)

	if type(props.onChange) == "function" then
		editor:setChangeHandler(props.onChange)
	end

	return editor
end

TextEditor.id = "textEditor"
TextEditor.kind = "editor"
TextEditor.title = "Text Editor"
TextEditor.summary = "A native NSTextView editor with syntax highlighting, file watching, and optional live callbacks."
TextEditor.capabilities = { "text", "syntaxHighlight", "fileWatch" }
TextEditor.activation = {
	onFileExtension = { "lua", "txt", "md" },
	onCommand = { "openTextEditor" },
}
TextEditor.create = createEditor

local registered = App.getPlugin(TextEditor.id)
if not registered then
	registered = App.registerPlugin(TextEditor)
end

TextEditor.spec = registered

return registered
