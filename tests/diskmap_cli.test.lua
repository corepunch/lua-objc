_G.__headless = true
local t = require("TestKit")

local file = assert(io.open("Makefile", "r"))
local makefile = file:read("*a")
file:close()
local recipe = assert(makefile:match("run%-diskmap:[^\n]*\n([^\n]+)"))
t.assertEqual(recipe, "\t./$(TARGET) apps/diskmap/init.lua", "run-diskmap launches Diskmap without a root argument")
t.expect(not recipe:find("DIR", 1, true), "run-diskmap ignores DIR")

os.exit(t.summary() and 0 or 1)
