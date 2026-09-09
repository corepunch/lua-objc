_G.__headless = true
local t = require("TestKit")
local count = require("parity.contracts").run(require("ns"))
t.assertEqual(count, 83, "shared native stack contracts run without a window")
os.exit(t.summary() and 0 or 1)
