_G.__headless = true
local ns = require("AppKit")
local t = require("TestKit")
local xml = require("ui.xml")

-- Setting a window's size from Lua is a resize, so it obeys the window's
-- minimum as a user's drag does. Captures pass --width/--height through the
-- same setter; a layout audit must never see a size no user can reach.
local config = xml.render('<Window width="1100" height="760" minWidth="950" minHeight="580"><VStack /></Window>', {}, ns)
local window = ns.Window(config)
t.assertSize(window, 1100, 760, "initial size")

window.size = ns.Size(760, 468)
t.assertSize(window, 950, 580, "below the minimum clamps to it")

window.size = ns.Size(800, 900)
t.assertSize(window, 950, 900, "each dimension clamps on its own")

window.size = ns.Size(1400, 1000)
t.assertSize(window, 1400, 1000, "above the minimum is unchanged")

window:close()
os.exit(t.summary() and 0 or 1)
