_G.__headless = true
local t = require("TestKit")
local result, _, code = os.execute("ruby fastlane/studio_test.rb")
t.expect(result == true and code == 0, "Fastlane Studio preparation and build contracts")
os.exit(t.summary() and 0 or 1)
