local Onboarding = {}
Onboarding.__index = Onboarding

-- First-launch tour after the Kree8 / FlightElite pattern: one idea per
-- screen, Skip always visible, personalization before the library. The
-- last screen names a first story so a new reader can start in one tap.
local STEPS = { "welcome", "play", "audience", "worlds", "ready" }

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

function Onboarding.new(initial)
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
	}, Onboarding)
end

function Onboarding.steps() return STEPS end
function Onboarding.audiences() return AUDIENCE end

function Onboarding:needed()
	return self.completed ~= true
end

function Onboarding:stepIndex()
	return indexOf(STEPS, self.step) or 1
end

function Onboarding:isLast()
	return self:stepIndex() == #STEPS
end

function Onboarding:canAdvance()
	if self.step == "audience" then return self.audience ~= nil end
	return true
end

function Onboarding:next()
	if not self:canAdvance() then return false end
	local index = self:stepIndex()
	if index >= #STEPS then return false end
	self.step = STEPS[index + 1]
	return true
end

function Onboarding:back()
	local index = self:stepIndex()
	if index <= 1 then return false end
	self.step = STEPS[index - 1]
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
	for _, game in ipairs(adventures:list()) do
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
		stepIndex = index - 1,
		stepNumber = index,
		stepCount = #STEPS,
		canBack = index > 1,
		canAdvance = self:canAdvance(),
		isLast = self:isLast(),
		audience = audience,
		audienceId = self.audience,
		worlds = self:worlds(adventures),
		recommendation = recommendation,
	}
end

return Onboarding
