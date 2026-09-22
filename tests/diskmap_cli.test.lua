_G.__headless = true
local t = require("TestKit")

local file = assert(io.open("Makefile", "r"))
local makefile = file:read("*a")
file:close()
local recipe = assert(makefile:match("run%-diskmap:[^\n]*\n([^\n]+)"))
t.assertEqual(recipe, "\t./$(TARGET) apps/diskmap/init.lua $(or $(DIR),$(CURDIR))",
	"run-diskmap defaults to the repository root and accepts DIR")
t.expect(makefile:find("#        make run-diskmap DIR=~/Developer/icui", 1, true) ~= nil,
	"run-diskmap documents scanning a requested directory")

os.exit(t.summary() and 0 or 1)
