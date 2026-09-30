-- A script that declares itself headless exits when it returns, with or
-- without --test. Launched without the flag it used to enter the AppKit run
-- loop and idle there forever, holding every window and model it had built.
_G.__headless = true
local t = require("TestKit")

local path = os.tmpname()
local file = assert(io.open(path, "w"))
file:write("_G.__headless = true\nrequire('AppKit')\n")
file:close()

-- alarm survives exec, so a regression is killed by SIGALRM instead of
-- hanging the suite.
local WATCHDOG_SECONDS = 20
local ok, how, code = os.execute(string.format(
	"perl -e 'alarm %d; exec @ARGV' ./lua-objc %s >/dev/null 2>&1", WATCHDOG_SECONDS, path))
os.remove(path)
t.expect(ok == true and how == "exit" and code == 0,
	"a headless script exits on its own (" .. tostring(how) .. " " .. tostring(code) .. ")")

os.exit(t.summary() and 0 or 1)
