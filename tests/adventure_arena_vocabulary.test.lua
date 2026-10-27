_G.__headless = true
local t = require("TestKit")
local run = require("apps.adventure-arena.zilscript.tests.book_vocabulary")
-- Keep make test fast; the complete six-book matrix runs in lint-zil and
-- test-book-vocabulary inside zilscript.
local objects, commands = run("apps/adventure-arena/zilscript", t.expect, false, { "pocket-weather" })
t.assertEqual(objects, 25, "every Pocket Weather object has explicit vocabulary")
t.expect(commands >= 10, "literal phrases taught by examination resolve to their intended objects")
os.exit(t.summary() and 0 or 1)
