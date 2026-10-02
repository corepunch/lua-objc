local Onboarding = {}
Onboarding.__index = Onboarding

-- First-launch tour in two parts. The guide says what the app is and how a
-- story is read and played, one idea per page, each beside a screenshot of
-- the real reader. The setup that follows (after the Kree8 / FlightElite
-- pattern) asks who is playing and which worlds they like, and names a
-- first story so a new reader can start in one tap. Skip is always there.
-- Settings reopens the guide alone ("How to Play").
local GUIDE = { "welcome", "interactive", "read", "play" }
local SETUP = { "audience", "worlds", "ready" }
local STEPS = {}
for _, step in ipairs(GUIDE) do table.insert(STEPS, step) end
for _, step in ipairs(SETUP) do table.insert(STEPS, step) end

-- The guide's screenshots come from tour/capture.lua, which plays the
-- opening of an all-ages story in the iPhone Simulator, in light and dark.
local IMAGES = "apps/adventure-arena/tour/"

local AUDIENCE = {
	{ id = "kids", title = "Kids", symbol = "figure.and.child.holdinghands",
		detail = "Gentle worlds and introductory puzzles." },
	{ id = "parents", title = "Parents", symbol = "book.fill",
		detail = "The full shelf, including the darker classics." },
	{ id = "together", title = "Together", symbol = "person.2.fill",
		detail = "Stories that work read out loud." },
}

-- Horror stays off the kids shelf. The other genres come from the catalog.
local KIDS_HIDDEN = { ["Psychological Horror"] = true }

local function indexOf(list, id)
	for index, value in ipairs(list) do
		if value == id then return index end
	end
end

local function indexOfAudience(id)
	for _, option in ipairs(AUDIENCE) do
		if option.id == id then return option end
	end
end

-- `initial` is the saved snapshot. `options.touch` (true unless given):
-- the reader has a touch screen and an on-screen keyboard, so the guide
-- speaks of tapping and shows the suggestion bar above the keyboard. A Mac
-- has neither; the same pages speak of clicking there.
function Onboarding.new(initial, options)
	initial = initial or {}
	local interests = {}
	for _, genre in ipairs(initial.interests or {}) do
		table.insert(interests, genre)
	end
	return setmetatable({
		completed = initial.completed == true,
		step = indexOf(STEPS, initial.step) and initial.step or STEPS[1],
		audience = indexOfAudience(initial.audience) and initial.audience or nil,
		interests = interests,
		firstStory = initial.firstStory,
		touch = not options or options.touch ~= false,
		guideOnly = false,
	}, Onboarding)
end

function Onboarding.guide() return GUIDE end
function Onboarding.audiences() return AUDIENCE end

-- The whole tour on a first launch; the guide alone when it is reopened.
function Onboarding:steps()
	return self.guideOnly and GUIDE or STEPS
end

function Onboarding:needed()
	return self.completed ~= true
end

function Onboarding:stepIndex()
	return indexOf(self:steps(), self.step) or 1
end

function Onboarding:isLast()
	return self:stepIndex() == #self:steps()
end

function Onboarding:canAdvance()
	if self.step == "audience" then return self.audience ~= nil end
	return true
end

function Onboarding:next()
	if not self:canAdvance() then return false end
	local steps, index = self:steps(), self:stepIndex()
	if index >= #steps then return false end
	self.step = steps[index + 1]
	return true
end

function Onboarding:back()
	local index = self:stepIndex()
	if index <= 1 then return false end
	self.step = self:steps()[index - 1]
	return true
end

-- "How to Play": the guide again from its first page, without the setup.
-- The reader's audience, worlds and first story stay as they chose them.
function Onboarding:replay()
	self.guideOnly = true
	self.step = GUIDE[1]
	return true
end

function Onboarding:setAudience(id)
	if not indexOfAudience(id) then return false end
	self.audience = id
	return true
end

function Onboarding:hasInterest(genre)
	for _, existing in ipairs(self.interests) do
		if existing == genre then return true end
	end
	return false
end

function Onboarding:toggleInterest(genre)
	if type(genre) ~= "string" or genre == "" then return false end
	for index, existing in ipairs(self.interests) do
		if existing == genre then
			table.remove(self.interests, index)
			return true
		end
	end
	table.insert(self.interests, genre)
	return true
end

-- Kids never see horror tiles; everyone else sees the catalog genres.
function Onboarding:worlds(adventures)
	local worlds = {}
	for _, genre in ipairs(adventures and adventures:genres() or {}) do
		if not (self.audience == "kids" and KIDS_HIDDEN[genre.title]) then
			table.insert(worlds, {
				id = genre.id,
				title = genre.title,
				symbol = genre.symbol,
				tint = genre.tint,
				count = genre.count,
				selected = self:hasInterest(genre.title),
			})
		end
	end
	return worlds
end

-- Rank a first story from audience, picked worlds, and the catalog rating.
-- Kids never land on horror, even if they somehow selected it.
function Onboarding:recommend(adventures)
	if not adventures then return nil end
	local best, bestScore
	for _, game in ipairs(adventures:all()) do
		if not (self.audience == "kids" and KIDS_HIDDEN[game.genre]) then
			local score = game.rating or 0
			if self:hasInterest(game.genre) then score = score + 3 end
			if self.audience == "kids" and game.difficulty == "Introductory" then score = score + 2 end
			if self.audience == "kids" and game.genre == "Whimsical Adventure" then score = score + 1 end
			if self.audience == "together" and (game.difficulty == "Introductory" or game.difficulty == "Standard") then
				score = score + 1
			end
			if not bestScore or score > bestScore then
				best, bestScore = game, score
			end
		end
	end
	self.firstStory = best and best.id or nil
	return best
end

function Onboarding:complete()
	self.completed = true
	self.guideOnly = false
	self.step = STEPS[#STEPS]
	return true
end

function Onboarding:snapshot()
	local interests = {}
	for _, genre in ipairs(self.interests) do table.insert(interests, genre) end
	return {
		completed = self.completed,
		step = self.step,
		audience = self.audience,
		interests = interests,
		firstStory = self.firstStory,
	}
end

local function screenshot(id)
	return IMAGES .. id .. "-light.jpg", IMAGES .. id .. "-dark.jpg"
end

-- What one page says. A guide page has a screenshot and, where it explains
-- parts of the reader, a legend: one row for each part. `primary` names the
-- action of the button at the foot: next, done, startStory or browse.
function Onboarding:page(recommendation)
	local step = self.step
	local tap = self.touch and "Tap" or "Click"
	local page = { id = step, primary = "next", action = "Continue" }
	if step == "welcome" then
		page.symbol = "books.vertical.fill"
		page.title = "A book that answers back"
		page.detail = "Adventure Arena is a shelf of interactive stories. Each one opens like a book and puts you inside it: you are the main character."
		page.action = "Get Started"
		page.image, page.darkImage = screenshot(step)
	elseif step == "interactive" then
		page.symbol = "arrow.triangle.branch"
		page.title = "Not a book you read. A book you play."
		page.detail = "A printed book tells everyone the same story. Here the story stops and waits for you: say what you do, and it writes what happens next. Your place is saved after every move."
		page.image, page.darkImage = screenshot(step)
	elseif step == "read" then
		page.symbol = "text.book.closed.fill"
		page.title = "How to read a page"
		page.image, page.darkImage = screenshot(step)
		page.rows = {
			{ symbol = "mappin.and.ellipse", title = "The heading is where you are",
				detail = "Each new place opens with its name and what you find there." },
			{ symbol = "figure.walk", title = "Capitals are your moves",
				detail = "What you did, set apart from the story's answer." },
			{ symbol = "hand.tap.fill", title = "Underlined words are things you can use",
				detail = tap .. " one to see what you can do with it." },
		}
	elseif step == "play" then
		page.symbol = "text.bubble.fill"
		page.title = "How to play"
		page.rows = {
			{ symbol = "keyboard", title = "Type what you do",
				detail = "A word or two is enough: LOOK, TAKE BROOM, NORTH." },
			{ symbol = "hand.tap.fill", title = "Or " .. tap:lower() .. " an underlined word",
				detail = "Its menu lists what you can do with it. No typing needed." },
			{ symbol = "plus.circle.fill", title = "Stuck? " .. tap .. " +",
				detail = "Look Around and Inventory say where you are and what you carry." },
		}
		-- The keyboard and its suggestion bar belong to the phone.
		if self.touch then
			page.image, page.darkImage = screenshot(step)
			table.insert(page.rows, 2, { symbol = "ellipsis.bubble.fill", title = "Or tap a suggestion",
				detail = "As you type, the bar above the keyboard offers ways to finish." })
		end
	elseif step == "audience" then
		page.symbol = "person.2.fill"
		page.title = "Who is playing?"
		page.detail = "We'll put the right shelf first. You can change this later."
	elseif step == "worlds" then
		page.symbol = "globe.desk.fill"
		page.title = "Worlds you like"
		page.detail = "Pick as many as you want. We'll open with a story from those shelves."
	elseif step == "ready" then
		page.symbol = "sparkles"
		if recommendation then
			page.title = recommendation.title
			page.detail = recommendation.shortDescription
			page.primary, page.action = "startStory", "Start Reading"
		else
			page.title = "Your library is ready"
			page.detail = "Browse the shelves and open any cover."
			page.primary, page.action = "browse", "Browse the Library"
		end
	end
	if self.guideOnly and self:isLast() then page.primary, page.action = "done", "Done" end
	return page
end

-- One payload per screen so the template never branches on controller state.
function Onboarding:presentation(adventures)
	local index = self:stepIndex()
	local recommendation = self.step == "ready" and self:recommend(adventures) or nil
	local audience = {}
	for _, option in ipairs(AUDIENCE) do
		table.insert(audience, {
			id = option.id,
			title = option.title,
			symbol = option.symbol,
			detail = option.detail,
			selected = self.audience == option.id,
		})
	end
	return {
		step = self.step,
		stepNumber = index,
		stepCount = #self:steps(),
		canBack = index > 1,
		canAdvance = self:canAdvance(),
		isLast = self:isLast(),
		-- A reopened guide is closed, not skipped: there is nothing after it.
		dismissTitle = self.guideOnly and "Done" or "Skip",
		page = self:page(recommendation),
		audience = audience,
		audienceId = self.audience,
		worlds = self:worlds(adventures),
		recommendation = recommendation,
	}
end

return Onboarding
