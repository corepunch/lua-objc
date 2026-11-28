local CharacterSheet = require("apps.adventure-arena.services.CharacterSheet")
local Quotes = require("apps.adventure-arena.helpers.Quotes")
local ReaderStatus = require("apps.adventure-arena.helpers.ReaderStatus")
local Languages = require("apps.adventure-arena.helpers.Languages")
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
	hapticInterval = (4 / 30) / 1.75, hapticStyle = "soft", hapticIntensity = 0.5,
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
		-- The app's words in its current language (resources.xml).
		resources = assert(options.resources, "resources are required"),
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
		onClose = options.onClose or function() end,
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
	self.game = game
	if not ok then
		self.push("pages/SessionError", {
			title = game.title, message = err, actions = { back = self.back },
		})
		return false
	end
	self:cancelDictation()
	self.speech = nil
	local speechAvailable = self.speechModule ~= nil
	if speechAvailable then
		-- Dictation listens in the story's language, not the phone's.
		local locale = game.language and Languages.speechLocale(game.language)
		self.speech = self.speechModule.recognizer(function(state, text, message)
			self:onSpeechEvent(state, text, message)
		end, locale)
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
		dictate = function() self:toggleDictation() end,
		readingSettings = function() self:showReadingSettings() end,
		exportSheet = function() self:exportSheet() end,
	}
	local presentation = self.model:presentation()
	actions.disappear = function() self:onDisappear() end
	self.actions = actions
	self.draft, self.dictationStatus, self.toast, self.sheetError = "", "", nil, nil
	local pageRefs
	self.page, pageRefs = self.push("pages/Session", {
		roomTitle = presentation.roomTitle, phone = self.ns.idiom == "phone", actions = actions,
	})
	self.reader = self.mountTemplate(pageRefs.reader, "sections/Reader")
	self.heading = self.mountTemplate(pageRefs.heading, "sections/SessionTitle")
	if pageRefs.completions then
		self.completions = self.mountTemplate(pageRefs.completions, "sections/Completions")
	end
	self:render()
	self.transcript = self.mountTemplate(self.refs.transcript, "sections/Transcript")
	self:applyReadingSettings()
	-- A new story is read from its title page; a resumed one from its last line.
	self:scrollPage(saved and "bottom" or "top", false)
	return true
end

-- The page, its running head and its composer, drawn from the session, the
-- reading settings and the composer state. Every change to them draws again.
function Controller:readerData()
	local data = {}
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
	-- Commands are the story's own words: no autocorrection or capitals on
	-- any keyboard. On iPad a correction committed late could also replace
	-- a command with its first word.
	data.composer = { verbatim = true, dictate = self.speech ~= nil and not (hasText and not self.dictationActive), canSend = hasText }
	local engine = self.model.engine
	data.canExportSheet = engine and engine.canExportSheet and engine:canExportSheet()
	data.sheetError = self.sheetError
	data.toast = self.toast
	data.actions = self.actions
	return data
end

function Controller:render()
	if not self.reader or self.reader:isDisposed() then return end
	local data = self:readerData()
	self.refs = select(2, self.reader:update(data))
	local story = self.model:presentation()
	self.heading:update({
		roomTitle = story.roomTitle,
		progress = ReaderStatus.progress(self.resources(), self.game and self.game.statusLine, story.score, story.maxScore, story.moves),
		colorScheme = data.reading.colorScheme, font = data.reading.font,
	})
	self:renderCompletions()
end

function Controller:exportSheet()
	local engine = self.model.engine
	if not engine or not engine.characterSheet then return false end
	local ok, shared = pcall(function()
		local sheet = engine:characterSheet()
		return sheet and CharacterSheet.share(self.ns, sheet)
	end)
	self.sheetError = not ok or not shared
	self:render()
	return ok and shared
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
	self.refs = select(2, self.reader:update(self:readerData()))
	self:renderCompletions()
end

function Controller:renderCompletions()
	if self.completions then
		local choices = self.model:suggestions(self.draft)
		local actions = {}
		for i, choice in ipairs(choices) do
			actions["complete" .. i] = function()
				if choice.command then self:submitCommand(choice.command)
				else self:updateComposer(choice.text) end
			end
		end
		local reading = ReadingSettings:current():presentation()
		self.completions:update({ choices = choices, actions = actions,
			colorScheme = COLOR_SCHEMES[reading.appearance] or "system" })
	end
end

function Controller:renderTranscript()
	if not self.transcript or self.transcript:isDisposed() then return end
	local data = self.model:presentation()
	data.quoteRanges = Quotes.ranges
	local settings = ReadingSettings:current():presentation()
	data.reading = {
		font = settings.font, fontSize = settings.fontSize, lineSpacing = settings.lineSpacing,
		alignment = settings.alignment, primary = settings.primaryTextColor,
		secondary = settings.secondaryTextColor, rule = settings.ruleColor,
	}
	data.reveal = self:revealState(data.earlierEntries)
	self.transcriptEarlier = data.earlierEntries
	return self.transcript:update(data)
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

function Controller:beginTyping(firstEntry)
	local queue = {}
	for _, item in ipairs(self.model:paragraphsSince(firstEntry)) do
		item.length = characterCount(item.text)
		table.insert(queue, item)
	end
	if #queue == 0 or self.reduceMotion() then return end
	self.typingGeneration = (self.typingGeneration or 0) + 1
	local generation = self.typingGeneration
	self.typing = { queue = queue, position = 1, revealed = 0, hapticGeneration = 0, generation = generation }
	self.after(TYPING.tick, function() self:typeNext(generation) end)
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

function Controller:onSpeechEvent(state, text, message)
	if not self.refs then return end
	local resources = self.resources()
	local DICTATION = {
		listening = resources.dictationListening, starting = resources.dictationStarting,
		processing = resources.dictationProcessing, unavailable = resources.dictationUnavailable,
	}
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
		self.dictationStatus = self.resources().dictationProcessing
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
		self.dictationStatus = self.resources().dictationProcessing
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
	for _, name in ipairs({ "transcript", "heading", "reader", "completions" }) do
		if self[name] then self[name]:dispose() end
	end
	self.speech = nil
	self.refs = nil
	self.page = nil
	self.transcript, self.heading, self.reader, self.completions = nil, nil, nil, nil
	-- The shelves are behind the reader. Ask for their updated saves on return.
	self.onClose()
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
	self:render()
	self:renderTranscript()
	self:scrollToEntry(firstNew)
	self:announceScore(self.model:presentation().scoreChange)
	SavedGames:record(self.model:snapshot())
	return ok, err
end

-- Points are a moment: a success haptic and a glass capsule over the page
-- that fades after a beat, as Game Center achievements announce themselves.
function Controller:announceScore(change)
	if not self.refs or type(change) ~= "number" or change == 0 then return end
	self.toast = ReaderStatus.toast(self.resources(), change)
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
-- The UIKit host carries the reading theme behind system UI.
function Controller:applyReadingSettings()
	if not self.refs then return end
	if self.ns.platform == "UIKit" and self.page then
		local settings = ReadingSettings:current():presentation()
		self.page.overrideUserInterfaceStyle = settings.appearance
		-- The hosted reader stops at the keyboard guide, but the page
		-- continues behind the keyboard's rounded corners.
		self.page.view.backgroundColor = self.ns.Color(settings.pageColor)
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
