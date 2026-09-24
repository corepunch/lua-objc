_G.__headless = true
local t = require("TestKit")
local count = require("parity.composer_contracts").run(require("ns"))
t.assertEqual(count, 48, "composer geometry survives width and input-state round trips")
os.exit(t.summary() and 0 or 1)
