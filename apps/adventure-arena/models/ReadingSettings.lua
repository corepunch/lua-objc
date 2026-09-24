local ReadingSettings = {}
ReadingSettings.__index = ReadingSettings

local FONTS = { "default", "serif", "rounded", "monospaced" }
local THEMES = {
	{ id = "system", background = "background", primary = "primary", secondary = "secondary", appearance = 0 },
	{ id = "white", background = "#FFFFFF", primary = "#000000", secondary = "#4A4A4A", appearance = 1 },
	{ id = "sepia", background = "#F5E8D1", primary = "#2B1F14", secondary = "#6B4F33", appearance = 1 },
	{ id = "black", background = "#000000", primary = "#FFFFFF", secondary = "#ADADAD", appearance = 2 },
}

function ReadingSettings.new(initial)
	initial = initial or {}
	return setmetatable({
		font = initial.font or FONTS[1],
		fontSize = math.max(14, math.min(24, math.floor((initial.fontSize or 17) + 0.5))),
		theme = initial.theme or THEMES[1].id,
	}, ReadingSettings)
end

function ReadingSettings:setFontIndex(index)
	index = tonumber(index)
	if not index or index ~= math.floor(index) or not FONTS[index + 1] then return false end
	self.font = FONTS[index + 1]
	return true
end

function ReadingSettings:setFontSize(value)
	value = tonumber(value)
	if not value then return false end
	self.fontSize = math.max(14, math.min(24, math.floor(value + 0.5)))
	return true
end

function ReadingSettings:adjustFontSize(delta)
	return self:setFontSize(self.fontSize + delta)
end

function ReadingSettings:setThemeIndex(index)
	index = tonumber(index)
	if not index or index ~= math.floor(index) or not THEMES[index + 1] then return false end
	self.theme = THEMES[index + 1].id
	return true
end

function ReadingSettings:presentation()
	local fontIndex, themeIndex, theme
	for index, font in ipairs(FONTS) do
		if font == self.font then fontIndex = index - 1 end
	end
	for index, value in ipairs(THEMES) do
		if value.id == self.theme then themeIndex, theme = index - 1, value end
	end
	if not theme then themeIndex, theme = 0, THEMES[1] end
	return {
		font = self.font,
		fontIndex = fontIndex or 0,
		fontSize = self.fontSize,
		theme = theme.id,
		themeIndex = themeIndex,
		backgroundColor = theme.background,
		primaryTextColor = theme.primary,
		secondaryTextColor = theme.secondary,
		appearance = theme.appearance,
	}
end

return ReadingSettings
