-- Capture plans (lua/ui/capture.lua): the object a --capture-plan receives,
-- and how a plan's result becomes the process status. The window and the
-- process exit are stand-ins; `window:capture` itself is native and runs
-- only in a real launch (make diskmap-reel-captures).
_G.__headless = true
local t = require("TestKit")
local Capture = require("ui.capture")

local events = {}
local window = { capture = function(_, prefix) table.insert(events, "capture " .. prefix) end }
setmetatable(window, { __newindex = function(self, key, value)
	table.insert(events, key .. "=" .. value)
	rawset(self, key, value)
end })
local function sleep(seconds) table.insert(events, "sleep " .. seconds) end

local capture = Capture.new(window, sleep)
t.assertEqual(capture.window, window, "a plan reaches the app window")
t.assertEqual(capture.settle, 1, "shots settle for a second by default")
capture.appearance("dark")
capture.settle = 0.25
capture.shot("/tmp/page-dark")
capture.wait(2)
t.assertEqual(table.concat(events, ", "),
	"appearanceStyle=dark, sleep 0.25, capture /tmp/page-dark, sleep 2",
	"appearance switches the window; a shot settles, then captures")
t.assertThrows(function() capture.appearance("sepia") end, "an unknown appearance is an error")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p " .. dir)
local function plan(name, body)
	local path = dir .. "/" .. name .. ".lua"
	local file = assert(io.open(path, "w"))
	file:write(body)
	file:close()
	return path
end
local function run(path, app, win)
	local status
	Capture.run(path, app, win == nil and window or win, function(code) status = code end)
	return status
end

local app = { shown = {} }
function app:show(page) table.insert(self.shown, page) end
t.assertEqual(run(plan("ok", "return function(capture, app) app:show('map'); app:show('files') end"), app), 0,
	"a plan that returns exits with status 0")
t.assertEqual(table.concat(app.shown, " "), "map files", "a plan drives the app instance")
t.assertEqual(run(plan("fails", "return function() error('no such page') end"), app), 1,
	"a plan that raises exits with status 1")
t.assertEqual(run(plan("notfn", "return 42"), app), 1, "a plan must return a function")
t.assertEqual(run(plan("nowindow", "return function() end"), app, false), 1, "a plan needs an app window")

os.execute("rm -rf " .. dir)
os.exit(t.summary() and 0 or 1)
