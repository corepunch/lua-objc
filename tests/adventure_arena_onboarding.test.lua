_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Adventures = require("apps.adventure-arena.models.Adventures")
local Onboarding = require("apps.adventure-arena.models.Onboarding")
local OnboardingController = require("apps.adventure-arena.controllers.OnboardingController")
local Controller = require("apps.adventure-arena.Controller")
local Plan = require("apps.adventure-arena.tour.capture")

local catalog = Adventures.new()
local toymaker = catalog:find("books.wondertown")
local sanitarium = catalog:find("books.blackwood-horror")
t.expect(toymaker and sanitarium, "the catalog still has the all-ages and horror titles")

local function source(path)
	local file = assert(io.open(path, "rb")); local text = file:read("a"); file:close(); return text
end

-- A JPEG's pixel size, from its start-of-frame segment.
local function jpegSize(path)
	local file = io.open(path, "rb")
	if not file then return nil end
	local data = file:read("a"); file:close()
	local at = 3
	while at < #data do
		local marker, length = data:byte(at + 1), data:byte(at + 2) * 256 + data:byte(at + 3)
		if marker >= 0xC0 and marker <= 0xC2 then
			return data:byte(at + 7) * 256 + data:byte(at + 8), data:byte(at + 5) * 256 + data:byte(at + 6)
		end
		at = at + 2 + length
	end
end

-- ── The guide: what the app is, and how a story is read and played ───────
-- Four pages come first, each beside a screenshot of the real reader.
local fresh = Onboarding.new()
t.expect(fresh:needed(), "a new reader still needs the tour")
t.assertEqual(table.concat(fresh:steps(), " "), "welcome interactive read play audience worlds ready",
	"the guide comes before the setup")
t.assertEqual(table.concat(Onboarding.guide(), " "), "welcome interactive read play", "the guide has four pages")
t.assertEqual(fresh.step, "welcome", "the tour opens on the welcome page")

-- Every guide screenshot fills the tour's image box exactly, at three times
-- its size, in light and dark (tour/capture.sh crops them so), and the plan
-- has a shot for each.
local BOX = Plan.BOX
t.expect(source("apps/adventure-arena/views/Onboarding.etlua")
	:find("imageWidth = " .. BOX.width .. ", imageHeight = " .. BOX.height, 1, true) ~= nil,
	"the view's image box matches the capture plan")
local shots = {}
for _, shot in ipairs(Plan.SHOTS) do shots[shot.name] = shot end
local guide = Onboarding.new()
for index, step in ipairs(Onboarding.guide()) do
	t.assertEqual(guide.step, step, step .. " is guide page " .. index)
	local page = guide:presentation(catalog).page
	t.assertEqual(page.id, step, step .. " describes itself")
	t.expect(#page.title > 0 and (page.detail or page.rows), step .. " explains its screenshot")
	t.assertEqual(page.primary, "next", step .. " continues to the next page")
	t.expect(shots[step] ~= nil, step .. " has a shot in the capture plan")
	for _, path in ipairs({ page.image, page.darkImage }) do
		local width, height = jpegSize(path)
		t.expect(path:match("%.jpg$") ~= nil and width ~= nil, path .. " is a committed JPEG")
		t.expect(width == BOX.width * BOX.scale and height == BOX.height * BOX.scale, path .. " is exactly three times the box")
	end
	t.expect(guide:canAdvance() and guide:next(), step .. " can always continue")
end
t.assertEqual(guide.step, "audience", "the setup follows the guide")

-- The pages say what was asked of them: an interactive book, not a book;
-- how its page is read; how a move is made.
local pages = {}
local walk = Onboarding.new()
for _, step in ipairs(Onboarding.guide()) do
	pages[step] = walk:presentation(catalog).page
	walk:next()
end
t.expect(pages.welcome.detail:find("interactive stories", 1, true) ~= nil, "the welcome says what the app is")
t.expect(pages.interactive.title:find("play", 1, true) and pages.interactive.detail:find("waits for you", 1, true),
	"the second page says how this differs from a printed book")
t.expect(pages.interactive.detail:find("saved after every move", 1, true) ~= nil, "and that the reader's place is kept")
t.assertEqual(#pages.read.rows, 3, "reading a page has three parts: the heading, the reader's moves, the links")
t.assertEqual(#pages.play.rows, 4, "a touch reader has four ways to act")
t.expect(pages.play.rows[2].title:find("suggestion", 1, true) ~= nil, "one of them is the suggestion bar")
for _, row in ipairs(pages.play.rows) do
	t.expect(#row.symbol > 0 and #row.title > 0 and #row.detail > 0, row.title .. " has a symbol and a line of help")
end
-- The reader no longer has a compass; the tour must not teach one.
for _, path in ipairs({ "apps/adventure-arena/models/Onboarding.lua", "apps/adventure-arena/views/Onboarding.etlua" }) do
	t.expect(source(path):lower():find("compass", 1, true) == nil, path .. " does not mention the retired compass")
end

-- A Mac has no on-screen keyboard: no suggestion bar, no keyboard
-- screenshot, and the pages speak of clicking.
local mac = Onboarding.new(nil, { touch = false })
mac.step = "read"
t.expect(mac:page().rows[3].detail:find("Click", 1, true) ~= nil, "a Mac reader clicks an underlined word")
mac.step = "play"
local macPlay = mac:page()
t.expect(macPlay.image == nil, "a Mac does not show the phone keyboard")
t.assertEqual(#macPlay.rows, 3, "and does not offer the keyboard's suggestion bar")
for _, row in ipairs(macPlay.rows) do
	t.expect(not (row.title .. row.detail):lower():find("tap", 1, true), "no Mac row speaks of tapping: " .. row.title)
end

-- ── The setup: who is playing, which worlds, a first story ───────────────
fresh = guide
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
t.assertEqual(fresh:presentation(catalog).page.primary, "startStory", "the last page starts the recommended story")

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

-- With nothing to recommend the last page opens the library; its button
-- must not be a Continue that leads nowhere.
local empty = Onboarding.new()
empty.step = "ready"
local emptyPage = empty:presentation(Adventures.new { games = {} }).page
t.assertEqual(emptyPage.primary, "browse", "an empty catalog ends on Browse the Library")

-- "How to Play" reopens the guide alone and keeps what the reader chose.
t.expect(restored:replay() and restored.step == "welcome", "the guide reopens at its first page")
t.assertEqual(#restored:steps(), #Onboarding.guide(), "a reopened guide has no setup pages")
t.assertEqual(restored:presentation(catalog).dismissTitle, "Done", "a reopened guide is closed, not skipped")
for _ = 2, #Onboarding.guide() do restored:next() end
t.expect(restored:isLast() and not restored:next(), "the guide ends on how to play")
t.assertEqual(restored:presentation(catalog).page.primary, "done", "whose button closes it")
t.expect(restored:complete() and restored.audience == "kids" and restored:hasInterest("Whimsical Adventure"),
	"closing it leaves the reader's audience and worlds alone")
t.assertEqual(#restored:steps(), 7, "and the model is whole again")

-- ── Controller: the sheet is captured, never presented, so the tour can be
-- driven by the same actions the buttons fire. ─────────────────────────────
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

-- UIKit in name only: the pages a phone shows, built with AppKit's views.
local phone = setmetatable({ platform = "UIKit" }, { __index = ns })
tour = OnboardingController.new {
	adventures = catalog,
	store = store,
	ns = phone,
	presentSheet = function(sheet, sizes)
		presented, detents = sheet, sizes
		return sheet
	end,
	dismissSheet = function(sheet) dismissed = sheet end,
	openSession = function(id) opened = id return true end,
}

t.expect(tour:needed(), "the controller starts the tour for a new reader")
t.expect(tour.model.touch, "a phone reader taps")
local sheet, refs = tour:open()
t.expect(sheet ~= nil, "opening the tour presents a sheet")
t.assertEqual(detents[1], "large", "the tour uses the large detent so it reads as a first launch")
t.expect(refs.skip and refs.next, "welcome has Skip and Get Started")
t.assertEqual(refs.skip.title, "Skip", "a first-launch tour can be skipped")
t.assertEqual(refs.next.title, "Get Started", "the first page invites the reader in")
t.expect(not refs.back, "welcome has no Back")
t.expect(refs.shot_welcome ~= nil, "welcome shows a screenshot of the reader")
t.assertEqual(refs.step.stringValue, "1 of 7", "the head counts the pages")

-- The screenshot is laid out at exactly the image box.
local function layoutPage()
	tour.page.host.size = ns.Size(402, 760)
	tour.page.host:layout(402)
end
layoutPage()
t.assertSize(refs.shot_welcome, BOX.width, BOX.height, "the welcome screenshot")

tap("next")
t.assertEqual(tour.model.step, "interactive", "Get Started moves to the interactive-book page")
t.expect(tour.refs.back and tour.refs.shot_interactive, "later pages offer Back and their own screenshot")
t.expect(not tour.refs.shot_welcome, "and the previous screenshot is gone")
tap("next")
t.assertEqual(tour.model.step, "read", "Continue reaches how to read a page")

-- Alignment (AGENTS.md): in the legend every symbol is centered on one
-- vertical line and every title starts at one edge, whatever the symbols'
-- own widths.
local function windowX(view)
	local x = 0
	while view do
		x = x + view.frame.origin.x
		view = view.superview
	end
	return x
end
local function assertLegend(count, tag)
	layoutPage()
	local first
	for index = 1, count do
		local symbol, title = tour.refs["rowSymbol_" .. index], tour.refs["rowTitle_" .. index]
		t.expect(symbol ~= nil and title ~= nil, tag .. " row " .. index .. " has a symbol and a title")
		local row = { center = windowX(symbol) + symbol.frame.size.width / 2, label = windowX(title) }
		first = first or row
		t.expect(math.abs(row.center - first.center) < 0.01, tag .. " symbol " .. index .. " is centered on the column's line")
		t.expect(math.abs(row.label - first.label) < 0.01, tag .. " title " .. index .. " starts at the column's text edge")
		t.expect(row.label > row.center, tag .. " title " .. index .. " follows its symbol")
	end
	t.expect(tour.refs["rowSymbol_" .. (count + 1)] == nil, tag .. " has exactly " .. count .. " rows")
end
assertLegend(3, "how to read a page")
tap("next")
t.assertEqual(tour.model.step, "play", "Continue reaches how to play")
t.expect(tour.refs.shot_play ~= nil, "a phone sees the keyboard and its suggestions")
assertLegend(4, "how to play")
tap("back")
t.assertEqual(tour.model.step, "read", "Back returns to the previous page")
tap("next")
tap("next")
t.assertEqual(tour.model.step, "audience", "Continue reaches who-is-playing")
t.expect(tour.refs.hero_audience and not tour.refs.shot_play, "a setup page leads with its symbol")
tap("next")
t.assertEqual(tour.model.step, "audience", "Continue stays put until an audience is chosen")
tap("audience_kids")
t.assertEqual(tour.model.audience, "kids", "the kids card is stored")
tap("next")
t.assertEqual(tour.model.step, "worlds", "an audience choice unlocks worlds")
local kidsWorlds = tour.model:worlds(catalog)
t.expect(#kidsWorlds > 0, "the worlds screen lists tiles")
layoutPage()
local firstOffset
for index in ipairs(kidsWorlds) do
	local symbol = tour.refs["worldSymbol_" .. index]
	local label = tour.refs["worldTitle_" .. index]
	t.assertEqual(symbol.frame.size.width, 28, "world symbols share a fixed column")
	local offset = windowX(label) - windowX(tour.refs["world_" .. index])
	firstOffset = firstOffset or offset
	t.expect(math.abs(offset - firstOffset) < 0.01, "world labels start at the same inset in every tile")
end
tap("world_1")
t.expect(tour.model:hasInterest(kidsWorlds[1].title), "tapping a world selects it")
tap("next")
t.assertEqual(tour.model.step, "ready", "Continue reaches the first story")
t.expect(tour.refs.startStory and tour.refs.browse, "ready offers start and browse")
t.assertEqual(tour.refs.step.stringValue, "7 of 7", "the last page is the seventh")
tap("startStory")
t.assertEqual(opened, tour.model.firstStory, "Start Reading opens the recommended story")
t.expect(dismissed == presented, "finishing dismisses the sheet")
t.expect(saved and saved.completed == true, "finishing writes the completed flag")
t.expect(not tour:needed(), "the tour does not reopen after finish")
t.expect(tour:open() == nil, "opening again is a no-op once complete")

-- How to Play: the guide again, on its own.
presented, dismissed, opened = nil, nil, nil
local guideSheet, guideRefs = tour:openGuide()
t.expect(guideSheet ~= nil and presented == guideSheet, "How to Play presents the guide")
t.assertEqual(guideRefs.step.stringValue, "1 of 4", "the reopened guide has four pages")
t.assertEqual(guideRefs.skip.title, "Done", "and Done in place of Skip")
t.expect(tour:openGuide() == nil, "a second How to Play does not stack another sheet")
tap("next"); tap("next"); tap("next")
t.assertEqual(tour.model.step, "play", "the guide ends on how to play")
t.expect(tour.refs.done and not tour.refs.next, "whose button is Done")
tap("done")
t.expect(dismissed == guideSheet and tour.sheet == nil, "Done closes the guide")
t.expect(opened == nil, "closing the guide opens no story")
t.expect(saved.completed == true and saved.audience == "kids", "and the reader's choices are still saved")

local skipped = OnboardingController.new {
	adventures = catalog,
	store = { save = function() end },
	ns = ns,
	presentSheet = function(sheet) return sheet end,
	dismissSheet = function() end,
	openSession = function() return false end,
}
t.expect(not skipped.model.touch, "a Mac reader clicks")
skipped:open()
skipped:finish()
t.expect(not skipped:needed(), "Skip still completes the tour")

-- Wiring: the root controller owns a tour, headless launches leave it
-- closed, and Settings reopens the guide.
local app = Controller.new {
	adventures = catalog,
	ns = ns,
	saveStore = { load = function() end, save = function() end },
	readingStore = { load = function() end, save = function() end },
	onboardingStore = { load = function() end, save = function() end },
}
t.expect(app.onboarding and app.onboarding:needed(), "a new app still owes the tour")
t.expect(app.onboarding.sheet == nil, "headless create does not present the tour by itself")
app:createWindow()
t.expect(app.onboarding.sheet == nil, "nor does a headless window")
-- A glass button is its glass around the native button.
local function nativeButton(view)
	if view.className:find("Button", 1, true) then return view end
	for _, child in ipairs(view.subviews) do
		local button = nativeButton(child)
		if button then return button end
	end
end
local howToPlay = app.settings.refs.howToPlay and nativeButton(app.settings.refs.howToPlay)
t.expect(howToPlay ~= nil, "Settings offers How to Play")
t.assertEqual(howToPlay.title, "How to Play", "by name")
bridge._invokeAction(howToPlay)
t.expect(app.onboarding.sheet ~= nil and app.onboarding.model.guideOnly, "which opens the guide as a real sheet")
t.assertEqual(app.onboarding.refs.step.stringValue, "1 of 4", "from its first page")
app.onboarding:finish()

os.exit(t.summary() and 0 or 1)
