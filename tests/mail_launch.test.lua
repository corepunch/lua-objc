_G.__headless = true

local t = require("TestKit")

local appDir = "/private/tmp/lua-objc-mail-launch-app"
local statusPath = appDir .. "/status.txt"
local initPath = appDir .. "/init.lua"

assert(os.execute("mkdir -p " .. string.format("%q", appDir)))

local init = assert(io.open(initPath, "w"))
init:write(([[
local ns = require("AppKit")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local window = ns.Window {
		title = "Mail Launch Probe",
		width = 320,
		height = 240,
		ns.Text("hello"),
	}
	self.window = window

	ns.async(function()
		ns.sleep(1.0)
		local fh = assert(io.open(%q, "w"))
		local frame = window.frame
		local visible = window.screen and window.screen.visibleFrame or nil
		local targetX = visible and (visible.origin.x + (visible.size.width - frame.size.width) / 2) or -1
		local targetY = visible and (visible.origin.y + (visible.size.height - frame.size.height) / 2) or -1
		local dx = targetX >= 0 and math.abs(frame.origin.x - targetX) or -1
		local dy = targetY >= 0 and math.abs(frame.origin.y - targetY) or -1
		fh:write(string.format(
			"visible=%%s key=%%s main=%%s frame=%%.1f,%%.1f %% .1fx%%.1f visibleFrame=%%.1f,%%.1f %% .1fx%%.1f dx=%%.1f dy=%%.1f\n",
			tostring(window.isVisible),
			tostring(window.isKeyWindow),
			tostring(window.isMainWindow),
			frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
			visible and visible.origin.x or -1,
			visible and visible.origin.y or -1,
			visible and visible.size.width or -1,
			visible and visible.size.height or -1,
			dx, dy))
		fh:close()
		os.exit(0)
	end)

	return window
end

return Controller
]]):format(statusPath))
init:close()

local cmd = string.format("./lua-objc %q", appDir)
local ok = os.execute(cmd)

local status = assert(io.open(statusPath, "r")):read("*a")
local dx = tonumber(status:match("dx=([%d%.%-]+)"))
local dy = tonumber(status:match("dy=([%d%.%-]+)"))

t.expect(ok == true or ok == 0, "mail directory launch exits cleanly")
t.expect(status:find("visible=true") ~= nil, "mail directory launch makes the window visible")
t.expect(status:find("key=true") ~= nil, "mail directory launch makes the window key")
t.expect(status:find("main=true") ~= nil, "mail directory launch makes the window main")
t.expect(dx ~= nil and dy ~= nil and dx < 10 and dy < 10,
	"mail directory launch centers the window in the visible screen area")

os.exit(t.summary() and 0 or 1)
