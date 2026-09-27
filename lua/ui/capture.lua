-- Capture plans: `lua-objc --capture-plan=<plan.lua> <app> [app arguments]`
-- launches the app once and captures several of its states, where
-- `--capture` captures one state per launch. The plan file returns
-- `function(capture, app)`; `app` is the instance the framework created from
-- the entry point, so the plan changes pages through the app's own methods.
--
--   return function(capture, app)
--   	for _, appearance in ipairs({ "light", "dark" }) do
--   		capture.appearance(appearance)
--   		app:show("map")
--   		capture.shot("captures/map-" .. appearance)
--   	end
--   end
--
-- capture.shot(prefix) waits `capture.settle` seconds for layout, drawing and
-- appearance changes to finish, then writes <prefix>.png and
-- <prefix>.layout.xml exactly like --capture. The process exits when the
-- plan returns, with status 1 if it raised an error.
local ns = require("ns")

local Capture = {}

-- new(window, sleep) -> the `capture` object a plan receives; `sleep`
-- suspends the plan's coroutine without blocking the run loop.
function Capture.new(window, sleep)
	local capture = { window = window, settle = 1 }
	function capture.appearance(name)
		if name ~= "light" and name ~= "dark" and name ~= "system" then
			error("capture.appearance: expected light, dark or system, got " .. tostring(name), 2)
		end
		window.appearanceStyle = name
	end
	function capture.wait(seconds)
		sleep(seconds)
	end
	function capture.shot(prefix)
		sleep(capture.settle)
		window:capture(prefix)
		print(prefix)
	end
	return capture
end

-- run(path, app, window, exit): runs the plan at `path`, then calls `exit`
-- (os.exit unless given) with the process status.
function Capture.run(path, app, window, exit)
	exit = exit or os.exit
	if not window then
		io.stderr:write("capture plan: the app has no window\n")
		return exit(1)
	end
	local plan = dofile(path)
	if type(plan) ~= "function" then
		io.stderr:write("capture plan: " .. path .. " must return function(capture, app)\n")
		return exit(1)
	end
	ns.async(function()
		local ok, err = xpcall(plan, debug.traceback, Capture.new(window, ns.sleep), app)
		if not ok then io.stderr:write("capture plan: " .. tostring(err) .. "\n") end
		exit(ok and 0 or 1)
	end)
end

return Capture
