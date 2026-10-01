_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Template = require("ui.template")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Session = require("apps.adventure-arena.models.Session")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")

-- ── Markup ──────────────────────────────────────────────────────────────
local text, links = Session.parseLinks("A corroded [[brass plaque->plaque]] hangs on the [[gate]]. Go [[north]].")
t.assertEqual(text, "A corroded brass plaque hangs on the gate. Go north.", "the reader sees the labels")
t.assertEqual(#links, 3, "every marked run is a link")
t.assertEqual(links[1].location, 11, "a link starts where its label does, counted from 0")
t.assertEqual(links[1].length, 12, "a link is as long as its label")
t.assertEqual(links[1].label, "brass plaque", "a link keeps the words of the prose")
t.assertEqual(links[1].target, "plaque", "a link names the parser's word")
t.assertEqual(links[2].target, "gate", "a bare link is its own target")
t.assertEqual(text:sub(links[3].location + 1, links[3].location + links[3].length), "north", "later links follow the stripped text")

text, links = Session.parseLinks("Café — the [[Door]] is open.")
t.assertEqual(links[1].location, 11, "locations count characters, not bytes")
t.assertEqual(links[1].target, "door", "targets are lower case, as commands are")
t.assertEqual(text, "Café — the Door is open.", "labels keep their case")

text, links = Session.parseLinks("Nothing to tap here.")
t.assertEqual(text, "Nothing to tap here.", "plain prose is untouched")
t.assertEqual(#links, 0, "plain prose has no links")
text, links = Session.parseLinks("An [[]] empty link and an [[unclosed one.")
t.assertEqual(#links, 0, "empty and unclosed markup makes no link")
t.assertEqual(text, "An  empty link and an [[unclosed one.", "unclosed markup stays as written")
text, links = Session.parseLinks("")
t.assertEqual(text, "", "empty text stays empty")
t.assertEqual(#links, 0, "empty text has no links")

-- ── Actions for a tapped word ───────────────────────────────────────────
local state = { room = "Gate" }
local function engine()
	return { start = function()
		return {
			resume = function(_, command)
				if command == "north" then
					state.room = "Hall"
					return "Hall\nA [[grand staircase->staircase]] climbs away. The gate lies [[south]]."
				end
				return "You " .. command .. "."
			end,
			roomName = function() return state.room end,
			exits = function() return state.room == "Gate" and { "north" } or { "south" } end,
			items = function()
				if state.room ~= "Gate" then return { { "grand staircase", { "EXAMINE", "CLIMB" }, {} } } end
				return {
					{ "brass plaque", { "TAKE", "READ" }, {} },
					{ "iron gate", { "EXAMINE", "OPEN", "CLOSE", "UNLOCK" }, {} },
					{ "door to the operating theater", { "OPEN" }, {} },
				}
			end,
		}, "Gate\nThe rusted [[iron gates->gate]] stand open. A path leads [[north]].\nA [[brass plaque->plaque]] hangs askew."
	end }
end

local function commands(actions)
	local list = {}
	for _, action in ipairs(actions) do table.insert(list, action.command) end
	return table.concat(list, ",")
end

local model = Session.new { engineFactory = engine }
t.expect(model:start({ id = "links", title = "Links" }), "a story with links starts")
local scene = model:presentation().entries[1]
t.assertEqual(scene.paragraphs[1], "The rusted iron gates stand open. A path leads north.",
	"the transcript holds the prose without markup")
t.assertEqual(#scene.links[1], 2, "the first paragraph carries its links")
t.assertEqual(scene.paragraphs[2], "A brass plaque hangs askew.", "a single newline starts a separate object paragraph")
t.assertEqual(#scene.links[2], 1, "the object paragraph carries its own link")
t.assertEqual(scene.links[2][1].location, 2, "link offsets restart at each paragraph")
t.assertEqual(commands(model:linkActions("plaque")), "take plaque,read plaque",
	"readable text offers read instead of a duplicate examine, then the story's verbs by how often players use them")
t.assertEqual(model:linkActions("plaque")[1].title, "Take", "menu titles show only the capitalized verb")
local gateActions = model:linkActions("gate")
t.assertEqual(gateActions[1].title, "Examine", "the first button omits the object")
t.assertEqual(gateActions[2].title, "Open", "the second button omits the object")
t.assertEqual(gateActions[3].title, "Close", "the third button omits the object")
t.assertEqual(commands(model:linkActions("gate")), "examine gate,open gate,close gate",
	"verbs that need a second object are left out, and examine is offered once")
t.assertEqual(commands(model:linkActions("door")), "examine door,open door",
	"a target finds its object by any word of the object's name")
t.assertEqual(commands(model:linkActions("north")), "north", "a direction walks")
t.assertEqual(model:linkActions("north")[1].title, "Go north", "a direction's action says where it goes")
t.assertEqual(commands(model:linkActions("d")), "down", "direction abbreviations walk too")
t.assertEqual(commands(model:linkActions("ghost")), "examine ghost", "an unknown thing can still be examined")
t.assertEqual(#model:linkActions(""), 0, "an empty target offers nothing")

-- Overflow retains every supported action, with short titles and full commands.
local many = Session.new { engineFactory = engine }
many.items = { { name = "door", noun = "door", verbs = { "open", "close", "read", "take", "push", "pull", "touch" } } }
local overflow = many:linkActions("door")
t.assertEqual(#overflow, 7, "actions beyond three and the old six-item cap stay available")
for _, action in ipairs(overflow) do
	t.expect(not action.title:find("door", 1, true), "overflow labels omit the noun too")
	t.expect(action.command:find(" door$") ~= nil, "overflow commands retain their target")
end

-- ── The reader's page ───────────────────────────────────────────────────
state.room = "Gate"
local rendered
local controller = SessionController.new {
	model = model,
	findGame = function() return { id = "links", title = "Links" } end,
	push = function(_, data)
		local view, refs = xml.renderFile("apps/adventure-arena/views/Session.etlua", data, ns)
		rendered = { view = view, refs = refs }
		return view, refs
	end,
	back = function() end,
	ns = ns,
	readingSettings = ReadingSettings.new(),
	renderTemplate = function() end,
	mountTemplate = function(host, template)
		return Template.new(host, "apps/adventure-arena/views/" .. template .. ".etlua", ns)
	end,
	presentSheet = function() end,
	dismissSheet = function() end,
	reduceMotion = function() return true end,
}
t.expect(controller:show("links"), "the session opens")
local function page() return controller.transcript.refs end
local live = bridge._paragraphLinks(page().paragraph_1_1)
t.assertEqual(#live, 2, "the page marks the scene's links")
t.assertEqual(live[1].text, "iron gates", "a link underlines the words of the prose")
local plaque = bridge._paragraphLinks(page().paragraph_1_2)[1]
t.assertEqual(plaque.text, "brass plaque", "links in later lines keep their place")
t.assertEqual(table.concat(plaque.titles, ","), "Take,Read", "a link's menu lists its actions")
t.assertEqual(page().paragraph_1_1.text, scene.paragraphs[1], "the page shows the prose without markup")

bridge._paragraphPerformLink(page().paragraph_1_2, 1, 2)
t.assertEqual(model.history[#model.history], "read plaque", "choosing an action sends its command")
t.assertEqual(page().command_2.text, "read plaque", "the command appears on the page")
t.assertEqual(#bridge._paragraphLinks(page().paragraph_1_1), 2, "links stay live while the reader stays in the room")

bridge._paragraphPerformLink(page().paragraph_1_1, 2, 1)
t.assertEqual(model.history[#model.history], "north", "a direction link walks")
t.assertEqual(model:presentation().roomTitle, "Hall", "the reader arrives in the next room")
t.assertEqual(#bridge._paragraphLinks(page().paragraph_1_1), 0, "the words of a room left behind are plain prose")
local entries = model:presentation().entries
local hall = bridge._paragraphLinks(page()["paragraph_" .. #entries .. "_1"])
t.assertEqual(#hall, 2, "the new scene's links are live")
t.assertEqual(table.concat(hall[1].titles, ","), "Examine,Climb", "they offer the new room's verbs")
t.assertEqual(table.concat(hall[2].titles, ","), "Go south", "and the way back")

-- Reading settings re-set the page and keep its links.
controller.readingSettings:setJustified(true)
controller:applyReadingSettings()
hall = bridge._paragraphLinks(page()["paragraph_" .. #entries .. "_1"])
t.assertEqual(#hall, 2, "links survive a change of reading settings")
t.assertEqual(hall[1].text, "grand staircase", "re-set links stay on their words")

-- A resumed story rebuilds its links from the replayed commands.
state.room = "Gate"
local played = Session.new { engineFactory = engine, newSeed = function() return 1 end }
played:start({ id = "links", title = "Links" })
played:submit("north")
local save = played:snapshot()
state.room = "Gate"
local resumed = Session.new { engineFactory = engine }
t.expect(resumed:start({ id = "links", title = "Links" }, save), "a saved story resumes")
local last = resumed.entries[#resumed.entries]
t.assertEqual(last.links[1][1].target, "staircase", "replayed prose carries its links")

-- ── The real story ──────────────────────────────────────────────────────
local game = Adventures.new():find("books.blackwood-horror")
t.expect(game ~= nil, "the horror story is in the catalog")
if game then
	local story = Session.new { engineFactory = function(entry, seed) return ZILRuntime.new(entry, nil, seed) end }
	t.expect(story:start(game), "the horror story starts")
	local opening = story.entries[#story.entries]
	t.assertEqual(#opening.paragraphs, 2, "Sanitarium's gate and plaque print as separate paragraphs")
	local queue = story:paragraphsSince(#story.entries)
	t.assertEqual(#queue, 2, "the real opening has two paragraph reveal steps")
	local targets = {}
	for _, paragraphLinks in pairs(opening.links) do
		for _, link in ipairs(paragraphLinks) do targets[link.target] = true end
	end
	t.expect(targets.gate and targets.north and targets.plaque, "the opening links the gate, the path north and the plaque")
	t.expect(not table.concat(opening.paragraphs, "\n"):find("[[", 1, true), "no markup reaches the page")
	t.assertEqual(commands(story:linkActions("plaque")), "take plaque,read plaque",
		"the plaque offers the verbs the story accepts")
	story:submit("north")
	t.assertEqual(story.roomTitle, "Sanitarium Entrance Hall", "walking north enters the hall")
	t.assertEqual(#story.entries[#story.entries].paragraphs, 2, "the hall and its door print as separate paragraphs")
	story:submit("go back")
	t.assertEqual(story.roomTitle, "Sanitarium Gate", "GO BACK retraces the last step")
	story:submit("walk back")
	t.assertEqual(story.roomTitle, "Sanitarium Entrance Hall", "WALK BACK retraces it again")
	story:submit("north")
	local theater = table.concat(story.entries[#story.entries].paragraphs, "\n")
	t.expect(theater:find("slightly ajar", 1, true) ~= nil, "the cabinet is described")
	t.expect(not theater:find("scalpel", 1, true), "what the cabinet holds is not told at a glance")
	story:submit("examine cabinet")
	t.expect(table.concat(story.entries[#story.entries].paragraphs, "\n"):find("scalpel", 1, true) ~= nil,
		"examining the cabinet shows what it holds")

	-- A saved story replays "go back" to the same place.
	local replayed = Session.new { engineFactory = function(entry, seed) return ZILRuntime.new(entry, nil, seed) end }
	t.expect(replayed:start(game, story:snapshot()), "the story resumes from its commands")
	t.assertEqual(replayed.roomTitle, story.roomTitle, "replaying GO BACK ends in the same room")
	t.assertEqual(#replayed.entries, #story.entries, "the transcript is rebuilt whole")
end

os.exit(t.summary() and 0 or 1)
