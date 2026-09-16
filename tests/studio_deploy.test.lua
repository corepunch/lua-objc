_G.__headless = true
local t = require("TestKit")
local ok = os.execute("python3 scripts/ipad/test_deploy.py")
t.expect(ok == true or ok == 0, "iPad device discovery and signing selection")
os.exit(t.summary() and 0 or 1)
