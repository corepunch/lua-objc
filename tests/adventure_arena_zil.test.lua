_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Model = require("examples.adventure-arena.Model")
local ZIL = require("examples.adventure-arena.ZIL")

local ok, session = pcall(function() return ZIL.new(Model.games[1], ns) end)
t.expect(ok, "ZIL runtime loads the bundled Zork source")
if ok then
	local started, engine, opening = pcall(function()
		return session:start()
	end)
	t.expect(started, "ZIL runtime starts a game coroutine")
	if started then
		t.expect(tostring(opening):find("workshop", 1, true) ~= nil,
			"Wondertown opening text reaches the Lua UI")
	end
end

os.exit(t.summary() and 0 or 1)
