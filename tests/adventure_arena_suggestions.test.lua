_G.__headless = true
local t = require("TestKit")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Suggestions = require("apps.adventure-arena.zilscript.zilscript.reader.Suggestions")

local model = Session.new()
model.items = Suggestions.items({
	{ "brass plaque", { "READ", "TAKE" }, {}, nil, "brass plaque", false, { "plaque" }, { takeable = false } },
	{ "pebble", { "TAKE" } },
	{ "brass key", { "TAKE" }, {}, nil, "brass key" },
	{ "iron key", { "TAKE" }, {}, nil, "iron key" },
	{ "brass lamp", { "LAMP-ON" }, {}, { { verb = "turn", prefix = "on" } }, "brass lamp" },
})
model.exitList = { "east" }
local function titles(draft)
	local result = {}
	for _, choice in ipairs(model:suggestions(draft)) do table.insert(result, choice.title) end
	return table.concat(result, ",")
end
t.assertEqual(titles(" "), "Look around,Inventory", "blank composer offers the default commands")
t.assertEqual(model:suggestions("")[1].command, "look", "Look around is a complete command")
t.assertEqual(model:suggestions(nil)[2].command, "inventory", "Inventory is a complete command")
t.assertEqual(model:suggestions("T")[1].text, "take ", "T completes the first verb with a space")
t.assertEqual(titles("take p"), "pebble", "fixed plaque is excluded")
t.assertEqual(titles("read P"), "plaque", "short unique noun matches a qualified parser phrase")
t.assertEqual(model:suggestions("read p")[1].text, "read plaque ", "acceptance fills the draft")
t.assertEqual(titles("read br"), "brass plaque", "qualifier prefix also completes")
t.assertEqual(titles("take k"), "brass key,iron key", "ambiguous noun retains qualifiers")
t.assertEqual(titles("take "), "pebble,brass key,iron key", "only eligible objects, up to three")
t.assertEqual(titles("go "), "east", "only a current exit is offered")
t.assertEqual(titles("go west "), "", "no invented exits")
t.assertEqual(titles("xyz "), "", "unsupported verbs produce no suggestions")
t.assertEqual(titles("turn o"), "turn on", "multiword parser verb completes as a phrase")
t.assertEqual(titles("read plaque "), "", "complete command needs explicit submission")
t.assertEqual(#model.history, 0, "requesting suggestions cannot play a turn")
model.items = {}
t.assertEqual(titles("take "), "", "no stale nouns after moving")
model.running = false
t.assertEqual(titles("l"), "", "finished session is quiet")

local Runtime = require("apps.adventure-arena.services.ZILRuntime")
require("apps.adventure-arena.Store").new()
local blackwood = Session.new { engineFactory = function(game, seed) return Runtime.new(game, nil, seed) end }
t.expect(blackwood:start(require("apps.adventure-arena.models.Adventures"):find("books.blackwood-horror")), "Blackwood opens")
t.assertEqual(blackwood:suggestions("read p")[1].text, "read plaque ", "actual gate plaque is readable")
t.assertEqual(#blackwood:suggestions("take p"), 0, "fixed gate plaque cannot be taken")
os.exit(t.summary() and 0 or 1)
