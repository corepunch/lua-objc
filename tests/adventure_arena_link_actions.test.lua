_G.__headless = true
local t = require("TestKit")
local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local Suggestions = require("apps.adventure-arena.zilscript.zilscript.reader.Suggestions")
local model = Session.new()
local function pattern(verb, join, reverse)
	return { verb = verb, prefix = "", join = join, reverse = reverse }
end
model.items = {
	{ name = "tiny brass winding key", noun = "key", target = "winding key", carried = true,
		aliases = { "key" }, patterns = { pattern("drop") } },
	{ name = "workshop key", noun = "key", target = "workshop key", carried = true,
		aliases = { "key" }, patterns = { pattern("drop") } },
	{ name = "the fox", noun = "fox", target = "fox", patterns = {} },
	{ name = "patchy fox toy", noun = "toy", target = "patchy fox", aliases = { "fox", "nutmeg" },
		patterns = { pattern("tell", "about"), pattern("show", "to", true) }, traits = { actor = true } },
	{ name = "patient file", noun = "file", target = "patient file", carried = true,
		patterns = { pattern("show", "to"), pattern("read", "with") } },
}
model:beginScene("Workshop")
model:appendParagraph("The [[fox]] guards a [[workshop key]]. A [[wall]] is bare.")
local function has(target, command)
	for _, action in ipairs(model:linkActions(target)) do
		if action.command == command then return true end
	end
	return false
end
t.expect(has("workshop key", "drop workshop key"), "qualified key link resolves to the correct unique key")
t.expect(not has("workshop key", "drop winding key"), "same final noun cannot replace a different key")
t.expect(has("fox", "tell patchy fox about workshop key"), "vocabulary topic does not hide the actual fox's conversation")
t.expect(has("fox", "show patient file to patchy fox"), "actor menu puts evidence in the direct-object position")
t.expect(not has("fox", "show patchy fox to patient file"), "actor menu never reverses evidence and recipient")
t.expect(has("file", "show patient file to patchy fox"), "carried evidence can be shown to a present actor")
t.expect(not has("file", "show patient file to wall"), "show actions offer people as recipients")
t.expect(not has("file", "read patient file with patient file"), "instrument menus do not offer the object itself")
table.insert(model.items, { name = "wall", noun = "wall", target = "wall", patterns = { pattern("examine") } })
model.items[5].patterns = { { action = "GIVE-TO", verb = "give", prefix = "", join = "to" } }
t.expect(has("file", "give patient file to wall"), "authored custom gift grammar can intentionally accept a non-actor recipient")
local distinct = Suggestions.items {
	{ "winding key", {}, {}, {}, "winding key" },
	{ "workshop key", {}, {}, {}, "workshop key" },
}
t.assertEqual(#distinct, 2, "two distinct tools with one head noun remain independently addressable")
local topicAndObject = Suggestions.items {
	{ "workshop key", {}, {}, {}, "workshop key", false, {}, {}, 10 },
	{ "workshop key", { "EXAMINE" }, {}, { pattern("examine") }, "workshop key", true, {}, {}, 20 },
}
t.assertEqual(#topicAndObject, 2, "a vocabulary-only topic cannot swallow a physical object's identity")
model.items = topicAndObject
t.expect(has("workshop key", "examine workshop key"), "physical key remains addressable beside its topic")
-- A link is prose history, not proof that an actor or tool is still here.
local scoped = Session.new()
scoped.items = {
	{ name = "cloud", noun = "cloud", target = "cloud", identity = 1, patterns = { pattern("drizzle") } },
	{ name = "button", noun = "button", target = "button", identity = 2, carried = true, patterns = { pattern("drop") } },
	{ name = "report", noun = "report", target = "report", identity = 3, carried = true,
		patterns = { { verb = "steam", prefix = "", join = "over", partners = { [4] = true } } } },
	{ name = "kettle", noun = "kettle", target = "kettle", identity = 4, patterns = { pattern("examine") } },
}
scoped:beginScene("Kitchen")
scoped:appendParagraph("[[cloud]] [[button]] [[report]] [[kettle]] [[steam kettle->kettle]]")
local function contains(actions, command)
	for _, action in ipairs(actions) do if action.command == command then return true end end
	return false
end
t.expect(contains(scoped:linkActions("report"), "steam report over kettle"), "authored partner remains available")
t.expect(not contains(scoped:linkActions("report"), "steam report over cloud"), "unrelated local objects do not become authored instruments")
t.assertEqual(#scoped:linkActions("report"), 2, "partner aliases produce one action")
scoped.knownItems = { scoped.items[1], scoped.items[2] }
table.remove(scoped.items, 1)
table.remove(scoped.items, 1)
t.assertEqual(#scoped:linkActions("cloud"), 0, "an actor who has moved away has no stale local actions")
t.assertEqual(#scoped:linkActions("button"), 0, "giving away a tool removes its obsolete Drop action")
-- Conversation only offers nouns which the parser can actually resolve here.
local actor = { name = "Mica", noun = "mica", target = "mica", identity = 5,
	patterns = { pattern("tell", "about") }, traits = { actor = true } }
table.insert(scoped.items, actor)
scoped:appendParagraph("[[Mica->mica]] remembers [[button]].")
t.expect(not contains(scoped:linkActions("mica"), "tell mica about button"), "remembered physical exhibits are not local parser topics")
scoped.running = false
t.assertEqual(#scoped:linkActions("north"), 0, "finished readers offer no stale movement")
t.expect(not scoped:submit("look"), "finished readers do not resume a dead coroutine")
os.exit(t.summary() and 0 or 1)
