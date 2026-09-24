_G.__headless = true

local t = require("TestKit")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")

local settings = ReadingSettings.new()
local state = settings:presentation()
t.assertEqual(state.font, "default", "reading settings default to the system font")
t.assertEqual(state.fontSize, 17, "reading settings use the reference default size")
t.assertEqual(state.theme, "system", "reading settings follow the system theme by default")

t.expect(settings:setFontIndex(3), "font design can be changed by segmented index")
t.assertEqual(settings:presentation().font, "monospaced", "font selection maps to native font design")
t.expect(not settings:setFontIndex(4), "font selection rejects an unknown option")
t.expect(settings:setFontSize(24.4), "font size accepts numeric changes")
t.assertEqual(settings:presentation().fontSize, 24, "font size rounds to the nearest point")
settings:adjustFontSize(1)
t.assertEqual(settings:presentation().fontSize, 24, "font size clamps at the maximum")
settings:setFontSize(13)
t.assertEqual(settings:presentation().fontSize, 14, "font size clamps at the minimum")

t.expect(settings:setThemeIndex(2), "reading theme can be changed by segmented index")
state = settings:presentation()
t.assertEqual(state.theme, "sepia", "theme selection maps to sepia")
t.assertEqual(state.backgroundColor, "#F5E8D1", "sepia uses the reference paper color")
t.assertEqual(state.primaryTextColor, "#2B1F14", "sepia uses the reference ink color")
t.expect(not settings:setThemeIndex(-1), "theme selection rejects an unknown option")

os.exit(t.summary() and 0 or 1)
