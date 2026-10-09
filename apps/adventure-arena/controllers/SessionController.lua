local Adventures = require("apps.adventure-arena.models.Adventures")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local SavedGames = require("apps.adventure-arena.models.SavedGames")

local Controller = {}
Controller.__index = Controller

-- How long the "+5 points" glass capsule stays over the page.
local TOAST = { seconds = 2.2 }

-- Printing and haptic pulses have independent clocks, so every pulse has
-- the same spacing regardless of word length or the character reveal rate.
local TYPING = {
	tick = 1 / 30, charactersPerTick = 3,
	hapticInterval = (4 / 30) / 1.75, hapticStyle = "soft", hapticIntensity = 0.5, openingDelay = 0.45,
}

local function characterCount(text)
	return utf8.len(text) or #text
end

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "session model is required"),
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		ns = assert(options.ns, "native platform module is required"),
		readingOptions = options.readingOptions,
		renderTemplate = assert(options.renderTemplate, "template renderer is required"),
		mountTemplate = assert(options.mountTemplate, "template mount is required"),
		presentSheet = assert(options.presentSheet, "sheet presenter is required"),
		dismissSheet = assert(options.dismissSheet, "sheet dismisser is required"),
		-- Moments: a haptic and a toast when the score changes.
		haptics = options.haptics,
		-- The Speech module, or nil where dictation is unavailable.
		speechModule = options.speech,
		after = options.after or function() end,
		reduceMotion = options.reduceMotion or function()
			return type(options.ns.reduceMotion) == "function" and options.ns.reduceMotion() == true
		end,
		onProgress = options.onProgress or function() end,
		speech = nil,
		dictationActive = false,
		dictationPrefix = "",
		-- What the reader shows besides the story: the command being typed,
		-- the dictation status line and the score capsule.
		draft = "",
		dictationStatus = "",
		toast = nil,
	}, Controller)
end

-- Reading settings name an appearance as UIKit does; the page takes it as
-- a colour scheme.
local COLOR_SCHEMES = { [1] = "light", [2] = "dark" }

-- Opens a story at its last page when it has an autosave, or from its title
-- page when `fresh` is set or nothing is saved.
function Controller:show(id, fresh)
	local game = Adventures:find(id)
	if not game then return false end
	local saved = not fresh and SavedGames:find(id) or nil
	self:finishTyping()
	local ok, err = self.model:start(game, saved)
	if not ok then
		self.push("pages/SessionError", {
			title = game.title, message = err, actions = { back = self.back },
		})
		return false
	end
	self:cancelDictation()
	local speechAvailable = self.speechModule ~= nil
	if speechAvailable then
		self.speech = self.speechModule.recognizer(function(state, text, message)
			self:onSpeechEvent(state, text, message)
		end)
	end
	local actions = {
		submit = function() self:submitCommand(self.draft) end,
		inputChanged = function(text) self:updateComposer(text) end,
		inputCommand = function(command)
			if command ~= "submit" then return false end
			self:submitCommand(self.draft)
			return true
		end,
		inputFocused = function() self:scrollTranscript(true) end,
		look = function() self:submitCommand("look") end,
		inventory = function() self:submitCommand("inventory") end,
		dictate = function() self:toggleDictation() end,
		close = function() self:close() end,
		readingSettings = function() self:showReadingSettings() end,
	}
	local presentation = self.model:presentation()
	actions.disappear = function() self:onDisappear() end
	self.actions = actions
	self.draft, self.dictationStatus, self.toast = "", "", nil
	local pageRefs
	self.page, pageRefs = self.push("pages/Session", { gameTitle = presentation.gameTitle, actions = actions })
	self.reader = self.mountTemplate(pageRefs.reader, "sections/Reader")
	self.heading = self.mountTemplate(pageRefs.heading, "sections/SessionTitle")
	self.suggestions = self.mountTemplate(pageRefs.suggestions, "sections/Suggestions")
	self:render()
	self.transcript = self.mountTemplate(self.refs.transcript, "sections/Transcript")
	-- A new story types its opening; a resumed one opens at its last line.
	if not saved then self:beginTyping(1, TYPING.openingDelay) end
	self:applyReadingSettings()
	self:renderSuggestions(self.draft)
	-- A new story is read from its title page; a resumed one from its last line.
	self:scrollPage(saved and "bottom" or "top", false)
	self.onProgress()
	return true
end

-- The page, its running head and its composer, drawn from the session, the
-- reading settings and the composer state. Every change to them draws again.
function Controller:readerData()
	local data = self.model:presentation()
	local settings = ReadingSettings:current():presentation()
	data.reading = {
		page = settings.pageColor, primary = settings.primaryTextColor, secondary = settings.secondaryTextColor,
		font = settings.font, fontSize = settings.fontSize,
		colorScheme = COLOR_SCHEMES[settings.appearance] or "system",
	}
	local hasText = self.draft:find("%S") ~= nil
	data.draft = self.draft
	data.dictation = { status = self.dictationStatus }
	-- With speech available the microphone stands where Send would, until
	-- there is something typed to send.
	data.composer = { dictate = self.speech ~= nil and not (hasText and not self.dictationActive), canSend = hasText }
	data.toast = self.toast
	data.actions = self.actions
	return data
end

function Controller:render()
	if not self.reader or self.reader:isDisposed() then return end
	local data = self:readerData()
	self.refs = select(2, self.reader:update(data))
	self.heading:update({ gameTitle = data.gameTitle, roomTitle = data.roomTitle, colorScheme = data.reading.colorScheme })
end

function Controller:isOpen()
	return self.refs ~= nil
end

-- Every scroll of the page goes through here: the native scroll view
-- scrolls, to a named place, at the request of a command or the keyboard.
function Controller:scrollPage(target, animated, anchor)
	local scroll = self.refs and self.refs.transcriptScroll
	if scroll then scroll:scrollTo(target, animated, anchor) end
end

function Controller:scrollTranscript(animated)
	self:scrollPage("bottom", animated == true)
end

-- The page already holds the whole answer (see “Typing”), so one smooth
-- scroll brings it into view: to the foot of the page when the answer fits
-- the screen, and otherwise no further than the command that asked for it,
-- so a long answer is read from its first line.
function Controller:scrollToEntry(entry)
	local id = "entry_" .. (entry - (self.transcriptEarlier or 0))
	if not (self.transcript and self.transcript.refs[id]) then return self:scrollTranscript(true) end
	self:scrollPage(id, not self.reduceMotion(), "top")
end

function Controller:updateComposer(text)
	if not self.refs then return end
	self.draft = type(text) == "string" and text or ""
	self:render()
	self:renderSuggestions(self.draft)
end

-- Suggestions follow every keystroke. A whole command ("north", "open
-- mailbox") runs on tap; a completion replaces the composer text so the
-- player can keep typing.
function Controller:renderSuggestions(text)
	if not self.suggestions or self.suggestions:isDisposed() then return end
	local suggestions = self.model:suggestions(type(text) == "string" and text or "")
	local actions = {}
	for index, suggestion in ipairs(suggestions) do
		actions["suggest_" .. index] = function() self:applySuggestion(suggestion) end
	end
	self.currentSuggestions = suggestions
	self.suggestions:update({ suggestions = suggestions, actions = actions })
end

function Controller:applySuggestion(suggestion)
	if not self.refs or type(suggestion) ~= "table" then return false end
	if suggestion.submit then return self:submitCommand(suggestion.text) end
	self:updateComposer(suggestion.text)
	return true
end

function Controller:renderTranscript()
	if not self.transcript or self.transcript:isDisposed() then return end
	local data = self.model:presentation()
	local settings = ReadingSettings:current():presentation()
	data.reading = {
		font = settings.font, fontSize = settings.fontSize, lineSpacing = settings.lineSpacing,
		alignment = settings.alignment, primary = settings.primaryTextColor,
		secondary = settings.secondaryTextColor, rule = settings.ruleColor,
	}
	data.reveal = self:revealState(data.earlierEntries)
	data.linkMenus, data.actions = self:linkMenus(data.entries)
	self.transcriptEarlier = data.earlierEntries
	return self.transcript:update(data)
end

-- Links are live in the scene the reader stands in: the words of earlier
-- rooms name things that are no longer at hand, so they are set as plain
-- prose. Returns the menus keyed "entry_paragraph", as the Transcript
-- template's paragraph ids are, and the action each menu item runs.
function Controller:linkMenus(entries)
	local menus, actions = {}, {}
	local first = #entries + 1
	for index = #entries, 1, -1 do
		first = index
		if entries[index].kind == "scene" then break end
	end
	for index = first, #entries do
		for paragraph, links in pairs(entries[index].links or {}) do
			local menu = {}
			for linkIndex, link in ipairs(links) do
				local items = {}
				for itemIndex, action in ipairs(self.model:linkActions(link.target)) do
					local name = table.concat({ "link", index, paragraph, linkIndex, itemIndex }, "_")
					actions[name] = function() self:submitCommand(action.command) end
					table.insert(items, { title = action.title, action = name })
				end
				if #items > 0 then
					table.insert(menu, {
						location = link.location, length = link.length, label = link.label, items = items,
					})
				end
			end
			if #menu > 0 then menus[index .. "_" .. paragraph] = menu end
		end
	end
	return menus, actions
end

-- ── Typing ──────────────────────────────────────────────────────────────
-- New prose is rendered whole and revealed by `revealedCharacters`, so its
-- lines never reflow as it types. Paragraphs still waiting are drawn clear
-- and a waiting scene's title is transparent, but all of it takes its space
-- at once: the page grows by the whole answer when the command is sent and
-- scrolls there once (`scrollToEntry`), rather than chasing each new line.
-- The template describes the reveal at each render (a command or a reading
-- settings change); between renders each tick writes the one paragraph
-- being typed.

function Controller:beginTyping(firstEntry, delay)
	local queue = {}
	for _, item in ipairs(self.model:paragraphsSince(firstEntry)) do
		item.length = characterCount(item.text)
		table.insert(queue, item)
	end
	if #queue == 0 or self.reduceMotion() then return end
	self.typingGeneration = (self.typingGeneration or 0) + 1
	local generation = self.typingGeneration
	self.typing = { queue = queue, position = 1, revealed = 0, hapticGeneration = 0, generation = generation }
	self.after(delay or TYPING.tick, function() self:typeNext(generation) end)
end

-- Everything typed so far stays; what is left appears at the next render.
function Controller:finishTyping()
	self.typing = nil
	self.typingGeneration = (self.typingGeneration or 0) + 1
end

function Controller:isTyping()
	return self.typing ~= nil
end

-- Revealed characters for each paragraph still typing, keyed as the
-- Transcript template's paragraph ids are ("3_1"), and each entry typing has
-- not reached yet (`waiting["3"]`, whose scene title stays transparent);
-- absent paragraphs show whole.
function Controller:revealState(earlier)
	local reveal = { waiting = {} }
	local typing = self.typing
	if not typing then return reveal end
	local current = typing.queue[typing.position]
	for position = typing.position, #typing.queue do
		local item = typing.queue[position]
		reveal[(item.entry - earlier) .. "_" .. item.paragraph] = position == typing.position and typing.revealed or 0
		if item.entry ~= current.entry or (item.paragraph == 1 and typing.revealed == 0) then
			reveal.waiting[tostring(item.entry - earlier)] = true
		end
	end
	return reveal
end

-- One pulse chain spans the entire reveal, including paragraph boundaries.
-- Generation checks keep callbacks from a superseded reveal silent.
function Controller:pulseTyping(generation, hapticGeneration)
	local typing = self.typing
	if not typing or typing.generation ~= generation or not typing.printing
		or typing.hapticGeneration ~= hapticGeneration
		or not self.transcript or self.transcript:isDisposed() then return end
	self.haptics.impact(TYPING.hapticStyle, TYPING.hapticIntensity)
	self.after(TYPING.hapticInterval, function() self:pulseTyping(generation, hapticGeneration) end)
end

function Controller:typeNext(generation)
	local typing = self.typing
	if not typing or typing.generation ~= generation or not self.transcript or self.transcript:isDisposed() then return end
	local item = typing.queue[typing.position]
	local refs, index = self.transcript.refs, item.entry - (self.transcriptEarlier or 0)
	local view = refs["paragraph_" .. index .. "_" .. item.paragraph]
	local from = typing.revealed
	if from == 0 and refs["sceneTitle_" .. index] then refs["sceneTitle_" .. index].opacity = 1 end
	typing.revealed = math.min(item.length, from + TYPING.charactersPerTick)
	local finished = typing.revealed >= item.length
	if view then view.revealedCharacters = finished and -1 or typing.revealed end
	if not typing.printing then
		typing.printing = true
		typing.hapticGeneration = typing.hapticGeneration + 1
		if self.haptics then self:pulseTyping(generation, typing.hapticGeneration) end
	end
	if finished then
		typing.position, typing.revealed = typing.position + 1, 0
		if typing.position > #typing.queue then
			self.typing = nil
			return
		end
		-- Add an optional paragraph pause here later: stop printing and delay
		-- the next tick; its first characters will restart the haptic chain.
	end
	self.after(TYPING.tick, function() self:typeNext(generation) end)
end

local DICTATION = {
	listening = "Listening… Tap the microphone to finish.",
	starting = "Waiting for microphone access…",
	processing = "Transcribing…",
	unavailable = "Dictation is unavailable. Check microphone and speech access in Settings.",
}

function Controller:onSpeechEvent(state, text, message)
	if not self.refs then return end
	local draft = self.draft
	if state == "listening" then
		self.dictationActive = true
		self.dictationStatus = DICTATION.listening
	elseif state == "partial" or state == "finished" then
		local separator = self.dictationPrefix ~= ""
			and not self.dictationPrefix:match("%s$") and " " or ""
		draft = self.dictationPrefix .. separator .. (text or "")
		if state == "finished" then
			self.dictationActive = false
			self.dictationStatus = ""
		end
	elseif state == "starting" then
		self.dictationStatus = DICTATION.starting
	elseif state == "processing" then
		self.dictationStatus = DICTATION.processing
	elseif state == "error" then
		self.dictationActive = false
		self.dictationStatus = message or DICTATION.unavailable
	elseif state == "idle" then
		self.dictationActive = false
		self.dictationStatus = ""
	end
	self:updateComposer(draft)
end

function Controller:toggleDictation()
	if not self.speech then return end
	if self.dictationActive then
		self.speech:stop()
		self.dictationStatus = DICTATION.processing
	else
		self.dictationPrefix = self.draft
		self.dictationActive = true
		self.speech:start()
	end
	self:updateComposer(self.draft)
end

function Controller:cancelDictation()
	if self.speech and self.dictationActive then self.speech:cancel() end
	self.dictationActive = false
end

function Controller:close()
	self:onDisappear()
	self.back()
end

function Controller:onDisappear()
	self:cancelDictation()
	self:finishTyping()
	for _, name in ipairs({ "transcript", "suggestions", "heading", "reader" }) do
		if self[name] then self[name]:dispose() end
	end
	self.speech = nil
	self.refs = nil
	self.page = nil
	self.transcript, self.suggestions, self.heading, self.reader, self.currentSuggestions = nil, nil, nil, nil, nil
	self.onProgress()
end

function Controller:submitCommand(command)
	if type(command) ~= "string" or not command:find("%S") then return false end
	self:cancelDictation()
	-- A command sets the rest of the previous answer at once, then the new
	-- answer types.
	self:finishTyping()
	local firstNew = self.model:entryCount() + 1
	local ok, err = self.model:submit(command)
	self:beginTyping(firstNew)
	self.dictationStatus = ""
	self:updateComposer("")
	self:renderTranscript()
	self:scrollToEntry(firstNew)
	self:announceScore(self.model:presentation().scoreChange)
	SavedGames:record(self.model:snapshot())
	self.onProgress()
	return ok, err
end

-- Points are a moment: a success haptic and a glass capsule over the page
-- that fades after a beat, as Game Center achievements announce themselves.
function Controller:announceScore(change)
	if not self.refs or type(change) ~= "number" or change == 0 then return end
	local points = math.abs(change) == 1 and "point" or "points"
	self.toast = string.format("%s%d %s", change > 0 and "+" or "−", math.abs(change), points)
	self:render()
	if self.haptics then
		if change > 0 then self.haptics.notification("success") else self.haptics.notification("warning") end
	end
	self.toastGeneration = (self.toastGeneration or 0) + 1
	local generation = self.toastGeneration
	self.after(TOAST.seconds, function()
		if self.refs and self.toastGeneration == generation then self.toast = nil; self:render() end
	end)
end

function Controller:showReadingSettings()
	local sheet, refs = self.renderTemplate("sheets/ReadingSettings", {
		actions = { done = function() self:closeReadingSettings() end },
	})
	self.readingSettingsRefs = refs
	if self.readingOptions then
		self.readingSettingsOptions = self.readingOptions:mount(refs.readingOptions, false)
	end
	self.readingSettingsSheet = self.presentSheet(sheet, { "medium", "large" })
	return true
end

-- Page colour, ink, face, size and leading belong to the page's
-- description, so a change draws the page again rather than restyling views.
-- The page's view controller is not a view: it takes a Night page's
-- appearance itself, so the status bar turns light.
function Controller:applyReadingSettings()
	if not self.refs then return end
	if self.ns.platform == "UIKit" and self.page then
		self.page.overrideUserInterfaceStyle = ReadingSettings:current():presentation().appearance
	end
	self:render()
	self:renderTranscript()
end

function Controller:closeReadingSettings()
	if self.readingOptions and self.readingSettingsOptions then
		self.readingOptions:unmount(self.readingSettingsOptions)
	end
	self.dismissSheet(self.readingSettingsSheet)
	self.readingSettingsSheet, self.readingSettingsRefs, self.readingSettingsOptions = nil, nil, nil
end

return Controller
