_G.__headless = true
local t = require("TestKit")

-- Offline signing and packaging contracts run through make test as well as CI.
local result, reason, code = os.execute("python3 -m unittest discover -s scripts/release -p 'test_*.py'")
t.expect(result == true and code == 0, "platform builds, Store signing, packaging and upload contracts: " .. tostring(reason))

local function read(path)
	local file = assert(io.open(path, "r"))
	local text = file:read("a")
	file:close()
	return text
end
local records = require("AppKit").json_parse(read("scripts/release/apps.json"))
for _, app in ipairs(records) do
	local entry = "apps/" .. app.app .. "/init.lua"
	local file = io.open(entry)
	t.expect(file ~= nil, app.app .. ": entry point exists")
	if file then file:close() end
	if app.platform == "macos" then
		local plist = read(app.plist)
		t.assertEqual(plist:match("<key>LuaObjCEntry</key>%s*<string>(.-)</string>"), entry,
			app.app .. ": launcher uses the app entry point")
	end
end
for _, path in ipairs({"scripts/release/release.py", "scripts/release/macos.mk"}) do
	t.expect(not read(path):find("xcodebuild", 1, true), path .. ": no Xcode build dependency")
end
t.summary()
