_G.__headless = true
local t = require("TestKit")
local count = require("parity.menu_contracts").run(require("ns"))
t.assertEqual(count, 10, "shared native menu contracts run without a window")
os.exit(t.summary() and 0 or 1)
