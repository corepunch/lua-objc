_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local Model = require("examples.adventure-arena.Model")
local ZIL = require("examples.adventure-arena.ZIL")
local originalOpen, originalPath, originalZilPath = io.open, package.path, package.zilpath

local ok, session = pcall(function() return ZIL.new(Model.game("books.wondertown"), ns) end)
t.expect(ok, "ZIL runtime loads the bundled Zork source")
if ok then
	local started, engine, opening = pcall(function()
		return session:start()
	end)
	t.expect(started, "ZIL runtime starts a game coroutine")
	if started then
		t.expect(tostring(opening):find("workshop", 1, true) ~= nil,
			"Wondertown opening text reaches the Lua UI")
		local resumed, response = pcall(function() return engine:resume("look") end)
		t.expect(resumed and type(response) == "string", "typed commands reach the runtime")
	end
end

t.assertEqual(io.open, originalOpen, "runtime restores host file IO")
t.assertEqual(package.path, originalPath, "runtime restores Lua import paths")
t.assertEqual(package.zilpath, originalZilPath, "runtime restores ZIL import paths")
t.assertThrows(function()
	ZIL.new(Model.game("books.wondertown"), {
		_readFile = function() error("fixture read failure") end,
	})
end, "stream read failures propagate")
t.assertEqual(io.open, originalOpen, "failed streamed load restores file IO")
t.assertEqual(package.path, originalPath, "failed streamed load restores Lua paths")
t.assertEqual(package.zilpath, originalZilPath, "failed streamed load restores ZIL paths")

os.exit(t.summary() and 0 or 1)
