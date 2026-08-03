local ns = require("AppKit")

local function Editor(props)
	props = props or {}

	local plugin = props.plugin
	if not plugin or type(plugin.create) ~= "function" then
		error("Editor requires props.plugin")
	end
	local editor = plugin.create {
		initialCode = props.initialCode,
		language = props.language or "lua",
	}

	return editor
end

return Editor
