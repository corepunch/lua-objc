_G.__headless = true
local t = require("TestKit")
local Suggestions = require("apps.adventure-arena.models.Suggestions")

local function titles(list)
	local result = {}
	for _, chip in ipairs(list) do table.insert(result, chip.title) end
	return table.concat(result, ",")
end

-- Engine room items as zilscript reports them: name, verbs, nested contents.
local items = Suggestions.items({
	{ "small mailbox", { "TAKE", "OPEN" }, { { "leaflet", { "TAKE", "READ" }, {} } } },
	{ "wooden table", { "EXAMINE", "PUT" }, {} },
	{ "door", { "OPEN", "LOOK-BEHIND" }, {} },
	{ "chasm", { "PUT" }, {} },
})
t.assertEqual(#items, 5, "nested contents are flattened")
t.assertEqual(items[1].noun, "mailbox", "multi-word names are typed by their final noun")
t.assertEqual(items[2].noun, "leaflet", "open containers reveal their contents")
t.assertEqual(items[4].verbs[2], "look behind", "engine action names become player words")
t.assertEqual(Suggestions.noun("Patrol-issue scrub brush"), "brush", "the noun is the last word")
t.assertEqual(#Suggestions.items(nil), 0, "missing engine data yields no items")

local context = { items = items, exits = { "north", "east", "up" } }
local empty = Suggestions.forInput("", context)
t.assertEqual(titles(empty), "north,east,open mailbox,take leaflet,look,inventory",
	"an empty composer offers exits, object actions and the basics")
for _, chip in ipairs(empty) do t.expect(chip.submit, "empty-composer chips are whole commands: " .. chip.title) end
t.expect(not titles(empty):find("put", 1, true), "verbs that need a second object are never one-tap commands")

local l = Suggestions.forInput("l", context)
t.assertEqual(l[1].title, "look", "L suggests look first")
t.assertEqual(l[1].text, "look ", "a verb completion leaves room to keep typing")
t.expect(not l[1].submit, "completions do not submit on their own")
t.expect(titles(l):find("take leaflet", 1, true), "L also finds the leaflet")

local tt = Suggestions.forInput("t", context)
t.assertEqual(tt[1].title, "take", "T suggests take first")
t.expect(titles(tt):find("examine table", 1, true), "T also offers the table")

local open = Suggestions.forInput("open ", context)
t.assertEqual(titles(open), "mailbox,door", "after a verb only objects that answer it are offered")
t.assertEqual(open[1].text, "open mailbox ", "an object completion extends the command")
t.assertEqual(titles(Suggestions.forInput("open d", context)), "door", "the partial word filters objects")
t.assertEqual(titles(Suggestions.forInput("examine ", context)), "table",
	"examine offers only what the story lists for it")
t.assertEqual(titles(Suggestions.forInput("smell ", context)), "mailbox,leaflet,table,door,chasm",
	"verbs the story does not list fall back to every object")
t.assertEqual(titles(Suggestions.forInput("put leaflet ", context)), "in,on,under,table,chasm",
	"a two-object verb offers its joining word")
t.assertEqual(titles(Suggestions.forInput("go ", context)):sub(1, 14), "north,east,up,", "go offers open exits first")
t.expect(Suggestions.forInput("go n", context)[1].submit, "a completed direction is a whole command")
t.assertEqual(titles(Suggestions.forInput("turn o", context)), "on,off", "two-word verbs complete their particle")

local none = Suggestions.forInput("xyzzy", context)
t.assertEqual(#none, 0, "unknown words produce no chips")
t.assertEqual(#Suggestions.forInput("", {}), 2, "no context still offers look and inventory")
local many = { items = {} }
for index = 1, 20 do table.insert(many.items, { noun = "thing" .. index, verbs = {} }) end
t.assertEqual(#Suggestions.forInput("examine ", many), 6, "chips are capped at six")
local known = Suggestions.forInput("read ", { items = {}, knownItems = { items[2] } })
t.assertEqual(titles(known), "leaflet", "objects remembered from earlier rooms stay suggestible")

os.exit(t.summary() and 0 or 1)
