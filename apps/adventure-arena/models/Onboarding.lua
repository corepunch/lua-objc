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

-- Words are the app's resources (resources.xml, one set per language): the
-- model holds their ids, and `presentation` takes the strings of the
-- language it speaks.
local AUDIENCE = {
	{ id = "kids", title = "audienceKids", symbol = "figure.and.child.holdinghands",
		detail = "audienceKidsDetail" },
	{ id = "parents", title = "audienceParents", symbol = "book.fill",
		detail = "audienceParentsDetail" },
	{ id = "together", title = "audienceTogether", symbol = "person.2.fill",
		detail = "audienceTogetherDetail" },
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
function Onboarding:page(recommendation, strings)
	local step = self.step
	local page = { id = step, primary = "next", action = strings.next }
	if step == "welcome" then
		page.symbol = "books.vertical.fill"
		page.title = strings.welcomeTitle
		page.detail = strings.welcomeDetail
		page.action = strings.getStarted
		page.image, page.darkImage = screenshot(step)
	elseif step == "interactive" then
		page.symbol = "arrow.triangle.branch"
		page.title = strings.interactiveTitle
		page.detail = strings.interactiveDetail
		page.image, page.darkImage = screenshot(step)
	elseif step == "read" then
		page.symbol = "text.book.closed.fill"
		page.title = strings.readTitle
		page.image, page.darkImage = screenshot(step)
		page.rows = {
			{ symbol = "mappin.and.ellipse", title = strings.readHeadingTitle, detail = strings.readHeadingDetail },
			{ symbol = "figure.walk", title = strings.readChevronTitle, detail = strings.readChevronDetail },
		}
	elseif step == "play" then
		page.symbol = "text.bubble.fill"
		page.title = strings.playTitle
		page.rows = {
			{ symbol = "keyboard", title = strings.playTypeTitle, detail = strings.playTypeDetail },
			{ symbol = "eye", title = strings.playLookTitle, detail = strings.playLookDetail },
		}

		if self.touch then
			page.image, page.darkImage = screenshot(step)
			table.insert(page.rows, 2, { symbol = "keyboard", title = strings.playSuggestionsTitle,
				detail = strings.playSuggestionsDetail })
		end
	elseif step == "audience" then
		page.symbol = "person.2.fill"
		page.title = strings.audienceTitle
		page.detail = strings.audienceDetail
	elseif step == "worlds" then
		page.symbol = "globe.desk.fill"
		page.title = strings.worldsTitle
		page.detail = strings.worldsDetail
	elseif step == "ready" then
		page.symbol = "sparkles"
		if recommendation then
			page.title = recommendation.title
			page.detail = recommendation.shortDescription
			page.primary, page.action = "startStory", strings.startReading
		else
			page.title = strings.readyTitle
			page.detail = strings.readyDetail
			page.primary, page.action = "browse", strings.browseLibrary
		end
	end
	if self.guideOnly and self:isLast() then page.primary, page.action = "done", strings.done end
	return page
end

-- One payload per screen so the template never branches on controller state.
function Onboarding:presentation(adventures, strings)
	local index = self:stepIndex()
	local recommendation = self.step == "ready" and self:recommend(adventures) or nil
	local audience = {}
	for _, option in ipairs(AUDIENCE) do
		table.insert(audience, {
			id = option.id,
			title = strings[option.title],
			symbol = option.symbol,
			detail = strings[option.detail],
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
		dismissTitle = self.guideOnly and strings.done or strings.skip,
		page = self:page(recommendation, strings),
		audience = audience,
		audienceId = self.audience,
		worlds = self:worlds(adventures),
		recommendation = recommendation,
	}
end

return Onboarding
