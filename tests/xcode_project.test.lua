_G.__headless = true
local t = require("TestKit")

local result, reason, code = os.execute("python3 scripts/ipad/test_xcode_project.py")
t.expect(result == true and code == 0, "Checked-in Xcode project's native source contract: " .. tostring(reason))
t.summary()
