_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Onboarding = require("apps.adventure-arena.models.Onboarding")
local OnboardingController = require("apps.adventure-arena.controllers.OnboardingController")
local Controller = require("apps.adventure-arena.Controller")

local catalog = Adventures.new()
local toymaker = catalog:find("books.wondertown")
local sanitarium = catalog:find("books.blackwood-horror")
t.expect(toymaker and sanitarium, "the catalog still has the all-ages and horror titles")

local fresh = Onboarding.new()
t.expect(fresh:needed(), "a new reader still needs the tour")
t.assertEqual(fresh.step, "welcome", "the tour opens on the welcome screen")
t.assertEqual(fresh:stepIndex(), 1, "welcome is the first step")
t.expect(fresh:canAdvance(), "welcome can always continue")
t.expect(fresh:next() and fresh.step == "play", "next reaches how-you-play")
t.expect(fresh:next() and fresh.step == "audience", "next reaches who-is-playing")
t.expect(not fresh:canAdvance(), "audience requires a choice")
t.expect(not fresh:next(), "audience does not advance without a choice")
t.expect(fresh:setAudience("kids"), "kids is a valid audience")
t.expect(fresh:canAdvance() and fresh:next() and fresh.step == "worlds", "a choice unlocks the worlds screen")

local worlds = fresh:worlds(catalog)
local titles = {}
for _, world in ipairs(worlds) do titles[world.title] = world end
t.expect(titles["Whimsical Adventure"], "kids see the gentle worlds")
t.expect(not titles["Psychological Horror"], "kids do not see horror worlds")
t.expect(fresh:toggleInterest("Whimsical Adventure") and fresh:hasInterest("Whimsical Adventure"),
	"a world can be selected")
t.expect(fresh:toggleInterest("Whimsical Adventure") and not fresh:hasInterest("Whimsical Adventure"),
	"the same world can be cleared")
t.expect(fresh:toggleInterest("Whimsical Adventure"), "the world is selected again")
t.expect(fresh:next() and fresh.step == "ready", "next reaches the first-story screen")
t.expect(not fresh:next(), "ready has no further step")

local pick = fresh:recommend(catalog)
t.assertEqual(pick.id, toymaker.id, "kids who like whimsical worlds start with the toymaker")
t.expect(fresh:complete() and not fresh:needed(), "finishing the tour clears the first-launch flag")

local restored = Onboarding.new(fresh:snapshot())
t.expect(not restored:needed(), "a saved snapshot does not show the tour again")
t.assertEqual(restored.audience, "kids", "audience survives a save")
t.expect(restored:hasInterest("Whimsical Adventure"), "world picks survive a save")
t.assertEqual(restored.firstStory, toymaker.id, "the recommended story is remembered")

local parent = Onboarding.new { audience = "parents", interests = { "Psychological Horror" } }
parent.step = "ready"
t.assertEqual(parent:recommend(catalog).id, sanitarium.id, "parents who pick horror start there")
t.expect(Onboarding.new { audience = "kids" }:worlds(catalog)[1], "kids still get a worlds list")

local parentsWorlds = Onboarding.new { audience = "parents" }:worlds(catalog)
local horrorVisible
for _, world in ipairs(parentsWorlds) do
	if world.title == "Psychological Horror" then horrorVisible = true end
end
t.expect(horrorVisible, "parents still see horror worlds")

-- Controller: the sheet is captured, never presented, so the tour can be
-- driven by the same actions the buttons fire.
local presented, detents, dismissed, opened
local saved
local store = {
	load = function() return saved end,
	save = function(value) saved = value end,
}
local tour
local function tap(id)
	local view = tour.refs[id]
	t.expect(view ~= nil, id .. " has a native button")
	-- Disabled controls do not send actions, just as a real click does not.
	if view and view.enabled then bridge._invokeAction(view) end
end

tour = OnboardingController.new {
	adventures = catalog,
	store = store,
	ns = ns,
	presentSheet = function(sheet, sizes)
		presented, detents = sheet, sizes
		return sheet
	end,
	dismissSheet = function(sheet) dismissed = sheet end,
	openSession = function(id) opened = id return true end,
}

t.expect(tour:needed(), "the controller starts the tour for a new reader")
local sheet, refs = tour:open()
t.expect(sheet ~= nil, "opening the tour presents a sheet")
t.assertEqual(detents[1], "large", "the tour uses the large detent so it reads as a first launch")
t.expect(refs.skip and refs.next, "welcome has Skip and Get started")
t.expect(not refs.back, "welcome has no Back")
tap("next")
t.assertEqual(tour.model.step, "play", "Get started moves to how-you-play")
t.expect(tour.refs.back, "later screens offer Back")
tap("next")
t.assertEqual(tour.model.step, "audience", "Continue reaches who-is-playing")
tap("next")
t.assertEqual(tour.model.step, "audience", "Continue stays put until an audience is chosen")
tap("audience_kids")
t.assertEqual(tour.model.audience, "kids", "the kids card is stored")
tap("next")
t.assertEqual(tour.model.step, "worlds", "an audience choice unlocks worlds")
local kidsWorlds = tour.model:worlds(catalog)
t.expect(#kidsWorlds > 0, "the worlds screen lists tiles")
tap("world_1")
t.expect(tour.model:hasInterest(kidsWorlds[1].title), "tapping a world selects it")
tap("next")
t.assertEqual(tour.model.step, "ready", "Continue reaches the first story")
t.expect(tour.refs.startStory and tour.refs.browse, "ready offers start and browse")
tap("startStory")
t.assertEqual(opened, tour.model.firstStory, "Start reading opens the recommended story")
t.expect(dismissed == presented, "finishing dismisses the sheet")
t.expect(saved and saved.completed == true, "finishing writes the completed flag")
t.expect(not tour:needed(), "the tour does not reopen after finish")
t.expect(tour:open() == nil, "opening again is a no-op once complete")

local skipped = OnboardingController.new {
	adventures = catalog,
	store = { save = function() end },
	ns = ns,
	presentSheet = function(sheet) return sheet end,
	dismissSheet = function() end,
	openSession = function() return false end,
}
skipped:open()
skipped:finish()
t.expect(not skipped:needed(), "Skip still completes the tour")

-- Wiring: the root controller owns a tour, but headless launches leave it closed.
local app = Controller.new {
	adventures = catalog,
	ns = ns,
	saveStore = { load = function() end, save = function() end },
	readingStore = { load = function() end, save = function() end },
	onboardingStore = { load = function() end, save = function() end },
}
t.expect(app.onboarding and app.onboarding:needed(), "a new app still owes the tour")
t.expect(app.onboarding.sheet == nil, "headless create does not present the tour by itself")

os.exit(t.summary() and 0 or 1)
