_G.__headless = true
local t = require("TestKit")

local file = assert(io.open("Makefile", "r"))
local makefile = file:read("*a")
file:close()
local recipe = assert(makefile:match("run%-diskmap:[^\n]*\n([^\n]+)"))
t.assertEqual(recipe, "\t./$(LUA_OBJC_BIN) apps/diskmap/init.lua --folder=$(or $(DIR),$(CURDIR))",
	"run-diskmap opens the repository root in the Folder Map and accepts DIR")
t.expect(makefile:find("#        make run-diskmap DIR=~/Developer/icui", 1, true) ~= nil,
	"run-diskmap documents opening a requested directory")

os.exit(t.summary() and 0 or 1)
