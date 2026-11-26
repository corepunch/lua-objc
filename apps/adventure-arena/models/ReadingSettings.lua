local Model = require("data.model")
local Languages = require("apps.adventure-arena.helpers.Languages")

-- The reader's settings, one row of the store's `reading` table:
-- `ReadingSettings:current()`. Changes are row methods; the controller
-- writes `snapshot()` to its document.
local ReadingSettings, Settings

-- Names of themes and line spacings are words of the app's language
-- (resources.xml: theme<Id>, spacing<Id>); the model knows their ids only.
-- The reader is a book first: New York (the system serif) by default, with
-- San Francisco, Rounded and Mono for readers who prefer them.
local FONTS = {
	{ id = "serif", title = "New York" },
	{ id = "default", title = "San Francisco" },
	{ id = "rounded", title = "Rounded" },
	{ id = "monospaced", title = "Mono" },
}

-- Apple Books-style pages. Each colour is a "light|dark" pair so the page
-- follows the system appearance; Night is a dark page at any time of day.
-- Ink is near-black on warm paper, never pure black on pure white.
local THEMES = {
	{ id = "paper", page = "#FBF9F4|#1C1B1F", ink = "#1D1C1A|#ECE9E2",
		secondary = "#6D6A64|#A19E97", rule = "#E4DFD4|#34323A", appearance = 0 },
	{ id = "original", page = "background", ink = "primary",
		secondary = "secondary", rule = "separator", appearance = 0 },
	{ id = "quiet", page = "#E9E9EC|#2A2A2E", ink = "#2A2A2E|#DADADF",
		secondary = "#6E6E75|#9C9CA3", rule = "#D3D3D8|#3C3C42", appearance = 0 },
	{ id = "night", page = "#000000", ink = "#D9D9DE",
		secondary = "#8E8E93", rule = "#2C2C2E", appearance = 2 },
}

-- Leading as a fraction of the type size: print books sit between 1.3 and
-- 1.5 line heights; "relaxed" suits large type on small screens.
local SPACING = {
	{ id = "compact", factor = 0.18 },
	{ id = "normal", factor = 0.32 },
	{ id = "relaxed", factor = 0.5 },
}

-- The app's language: "automatic" follows the device, as Languages names the rest.
local LANGUAGES = { "automatic" }
for _, language in ipairs(Languages.list()) do table.insert(LANGUAGES, language.id) end

local SIZE = { minimum = 14, maximum = 26, default = 18 }

local function indexOf(list, id)
	for index, value in ipairs(list) do
		if value.id == id then return index end
	end
end

-- A choice is one of its list's ids; the constraints refuse anything else.
local function oneOf(list, what)
	return function(_, id)
		if not indexOf(list, id) then return "Unknown " .. what .. "." end
	end
end

ReadingSettings, Settings = Model:extend("reading", {constraints = {
	font = oneOf(FONTS, "font"), theme = oneOf(THEMES, "theme"), spacing = oneOf(SPACING, "spacing"),
	language = function(_, id)
		for _, known in ipairs(LANGUAGES) do
			if known == id then return end
		end
		return "Unknown language."
	end,
}})

-- The row a saved snapshot restores to: anything unknown falls back to the
-- defaults, and the size is clamped.
function ReadingSettings.restore(initial)
	initial = initial or {}
	local row = ReadingSettings:load({
		id = "reader",
		font = indexOf(FONTS, initial.font) and initial.font or FONTS[1].id,
		fontSize = SIZE.default,
		theme = indexOf(THEMES, initial.theme) and initial.theme or THEMES[1].id,
		spacing = indexOf(SPACING, initial.spacing) and initial.spacing or "normal",
		justified = initial.justified == true,
		language = Languages.find(initial.language) and initial.language or "automatic",
	})
	row:setFontSize(initial.fontSize or SIZE.default)
	return row
end

-- The reader's one row.
function ReadingSettings:current()
	return self:find("reader")
end

function ReadingSettings.fonts() return FONTS end
function ReadingSettings.themes() return THEMES end
function ReadingSettings.spacings() return SPACING end

-- The language the app speaks now: the launch argument, else the reader's
-- choice, else the device's (the first preferred language with a catalog).
function ReadingSettings.language()
	local db = Model.db
	local row = db.reading and db.reading[1]
	if db.forcedLanguage then return db.forcedLanguage end
	if row and row.language and row.language ~= "automatic" then return row.language end
	return db.deviceLanguage or Languages.default()
end

-- Segmented pickers and theme buttons report zero-based indices.
local function select(self, key, list, index)
	index = tonumber(index)
	if not index or index ~= math.floor(index) or not list[index + 1] then return false end
	return self:update({[key] = list[index + 1].id}) == true
end

function Settings:setFontIndex(index) return select(self, "font", FONTS, index) end
function Settings:setThemeIndex(index) return select(self, "theme", THEMES, index) end
function Settings:setSpacingIndex(index) return select(self, "spacing", SPACING, index) end

-- The picker's choices after "Automatic" (a word of the app's language):
-- each language by its own name.
function ReadingSettings.languages()
	local choices = {}
	for _, language in ipairs(Languages.list()) do
		table.insert(choices, { id = language.id, title = language.title })
	end
	return choices
end
function Settings:languageIndex()
	for index, id in ipairs(LANGUAGES) do
		if id == self.language then return index - 1 end
	end
end
function Settings:setLanguageIndex(index)
	index = tonumber(index)
	if not index or index ~= math.floor(index) or not LANGUAGES[index + 1] then return false end
	return self:update({ language = LANGUAGES[index + 1] }) == true
end

-- Writes the row to the reader's settings document.
function Settings:persist()
	local document = Model.db.documents and Model.db.documents.reading
	if document and document.save then document.save(self:snapshot()) end
end

function Settings:setFontSize(value)
	value = tonumber(value)
	if not value then return false end
	self.fontSize = math.max(SIZE.minimum, math.min(SIZE.maximum, math.floor(value + 0.5)))
	return true
end

function Settings:adjustFontSize(delta)
	return self:setFontSize(self.fontSize + delta)
end

function Settings:setJustified(value)
	self.justified = value == true
	return true
end

-- Plain values for persistence; `ReadingSettings.restore(snapshot)` restores them.
function Settings:snapshot()
	return {
		font = self.font, fontSize = self.fontSize, theme = self.theme,
		spacing = self.spacing, justified = self.justified, language = self.language,
	}
end

function Settings:presentation()
	local fontIndex, themeIndex, spacingIndex = indexOf(FONTS, self.font), indexOf(THEMES, self.theme), indexOf(SPACING, self.spacing)
	local theme, spacing = THEMES[themeIndex], SPACING[spacingIndex]
	local themes = {}
	for index, value in ipairs(THEMES) do
		table.insert(themes, {
			index = index - 1, id = value.id, page = value.page,
			ink = value.ink, selected = index == themeIndex,
		})
	end
	return {
		font = self.font,
		fontIndex = fontIndex - 1,
		fontTitle = FONTS[fontIndex].title,
		fontSize = self.fontSize,
		minimumFontSize = SIZE.minimum,
		maximumFontSize = SIZE.maximum,
		lineSpacing = math.floor(self.fontSize * spacing.factor + 0.5),
		spacing = spacing.id,
		spacingIndex = spacingIndex - 1,
		justified = self.justified,
		alignment = self.justified and "justified" or "leading",
		theme = theme.id,
		themeIndex = themeIndex - 1,
		themes = themes,
		pageColor = theme.page,
		primaryTextColor = theme.ink,
		secondaryTextColor = theme.secondary,
		ruleColor = theme.rule,
		appearance = theme.appearance,
	}
end

return ReadingSettings
