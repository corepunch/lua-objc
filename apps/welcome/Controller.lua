local ns = require("AppKit")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	return ns.Window {
		title  = "Welcome",
		width  = 820,
		height = 520,
		ns.VStack {
			flexGrow = 1,
			alignment = "center",
			ns.Title "lua-objc",
			ns.Text "Build native apps with Lua and AppKit.",
		},
	}
end

return Controller
