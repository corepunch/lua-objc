local ReadingSettings = {}
ReadingSettings.__index = ReadingSettings

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
	{ id = "paper", title = "Paper", page = "#FBF9F4|#1C1B1F", ink = "#1D1C1A|#ECE9E2",
		secondary = "#6D6A64|#A19E97", rule = "#E4DFD4|#34323A", appearance = 0 },
	{ id = "original", title = "Original", page = "background", ink = "primary",
		secondary = "secondary", rule = "separator", appearance = 0 },
	{ id = "quiet", title = "Quiet", page = "#E9E9EC|#2A2A2E", ink = "#2A2A2E|#DADADF",
		secondary = "#6E6E75|#9C9CA3", rule = "#D3D3D8|#3C3C42", appearance = 0 },
	{ id = "night", title = "Night", page = "#000000", ink = "#D9D9DE",
		secondary = "#8E8E93", rule = "#2C2C2E", appearance = 2 },
}

-- Leading as a fraction of the type size: print books sit between 1.3 and
-- 1.5 line heights; "relaxed" suits large type on small screens.
local SPACING = {
	{ id = "compact", title = "Compact", factor = 0.18 },
	{ id = "normal", title = "Normal", factor = 0.32 },
	{ id = "relaxed", title = "Relaxed", factor = 0.5 },
}

local SIZE = { minimum = 14, maximum = 26, default = 18 }

local function indexOf(list, id)
	for index, value in ipairs(list) do
		if value.id == id then return index end
	end
end

function ReadingSettings.new(initial)
	initial = initial or {}
	local self = setmetatable({
		font = indexOf(FONTS, initial.font) and initial.font or FONTS[1].id,
		fontSize = SIZE.default,
		theme = indexOf(THEMES, initial.theme) and initial.theme or THEMES[1].id,
		spacing = indexOf(SPACING, initial.spacing) and initial.spacing or "normal",
		justified = initial.justified == true,
	}, ReadingSettings)
	self:setFontSize(initial.fontSize or SIZE.default)
	return self
end

function ReadingSettings.fonts() return FONTS end
function ReadingSettings.themes() return THEMES end
function ReadingSettings.spacings() return SPACING end

-- Segmented pickers and theme buttons report zero-based indices.
local function select(self, key, list, index)
	index = tonumber(index)
	if not index or index ~= math.floor(index) or not list[index + 1] then return false end
	self[key] = list[index + 1].id
	return true
end

function ReadingSettings:setFontIndex(index) return select(self, "font", FONTS, index) end
function ReadingSettings:setThemeIndex(index) return select(self, "theme", THEMES, index) end
function ReadingSettings:setSpacingIndex(index) return select(self, "spacing", SPACING, index) end

function ReadingSettings:setFontSize(value)
	value = tonumber(value)
	if not value then return false end
	self.fontSize = math.max(SIZE.minimum, math.min(SIZE.maximum, math.floor(value + 0.5)))
	return true
end

function ReadingSettings:adjustFontSize(delta)
	return self:setFontSize(self.fontSize + delta)
end

function ReadingSettings:setJustified(value)
	self.justified = value == true
	return true
end

-- Plain values for persistence; `ReadingSettings.new(snapshot)` restores them.
function ReadingSettings:snapshot()
	return {
		font = self.font, fontSize = self.fontSize, theme = self.theme,
		spacing = self.spacing, justified = self.justified,
	}
end

function ReadingSettings:presentation()
	local fontIndex, themeIndex, spacingIndex = indexOf(FONTS, self.font), indexOf(THEMES, self.theme), indexOf(SPACING, self.spacing)
	local theme, spacing = THEMES[themeIndex], SPACING[spacingIndex]
	local themes = {}
	for index, value in ipairs(THEMES) do
		table.insert(themes, {
			index = index - 1, id = value.id, title = value.title, page = value.page,
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
