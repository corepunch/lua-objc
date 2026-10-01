-- Capture harness for the tour's screenshots: the packager entry that
-- tour/capture.sh serves to the iPhone Simulator. It is the real app, with
-- its library kept in memory so a capture run never reads or writes the
-- reader's saved stories, followed by the capture plan (tour/capture.lua).
local ns = require("ns")
local App = require("apps.adventure-arena.Controller")
local Plan = require("apps.adventure-arena.tour.capture")

local Harness = {}
Harness.__index = Harness

local function memory(value)
	return { load = function() return value end, save = function(saved) value = saved end }
end

function Harness.new()
	return setmetatable({ app = App.new {
		saveStore = memory(), readingStore = memory(),
		-- The tour itself must not cover the pages being captured.
		onboardingStore = memory({ completed = true }),
	} }, Harness)
end

function Harness:createWindow()
	local window = self.app:createWindow()
	ns.async(function()
		local ok, err = xpcall(Plan.run, debug.traceback, self.app)
		if not ok then print("tour captures: " .. tostring(err)) end
	end)
	return window
end

return Harness
