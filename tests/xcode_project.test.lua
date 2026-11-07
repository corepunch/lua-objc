_G.__headless = true
local t = require("TestKit")

local result, reason, code = os.execute("python3 -m unittest discover -s scripts/xcode -p 'test_*.py'")
t.expect(result == true and code == 0, "Xcode generation and native source contracts: " .. tostring(reason))
t.summary()
