_G.__headless = true

local t = require("TestKit")

local template = assert(io.open(
	"examples/adventure-arena/views/Adventures.etlua", "r")):read("*a")
local controller = assert(io.open("examples/adventure-arena/Controller.lua", "r")):read("*a")
local detail = assert(io.open("examples/adventure-arena/views/Detail.lua", "r")):read("*a")

t.expect(template:find('<Button title="" action="featured" style="plain"', 1, true) ~= nil,
	"featured artwork is the navigation control")
t.expect(template:find('<Button title="" action="game_<%= index %>"', 1, true) ~= nil,
	"catalog artwork is the navigation control")
t.expect(template:find('<Label text="<%= game.title %>"', 1, true) ~= nil,
	"catalog titles are labels rather than buttons")
t.expect(template:find('<Button title="<%= game.title %>"', 1, true) == nil,
	"catalog titles do not navigate")
t.expect(detail:find('title = "Play Adventure"', 1, true) ~= nil
		and controller:find("self:showSession(game)", 1, true) ~= nil,
	"game detail starts the adventure session")

os.exit(t.summary() and 0 or 1)
