_G.__headless = true

-- The apps released as bundles (scripts/release/release.sh): each Xcode
-- project runs the shared launcher, its Info.plist names a Lua entry point
-- that exists, and its Copy Lua phase takes every kind of file the app reads
-- at run time. Diskmap's bundle once left out app.xml, and the app could not
-- start from its own Resources.
local t = require("TestKit")

local function read(path)
	local file = assert(io.open(path, "r"), "cannot read " .. path)
	local text = file:read("a")
	file:close()
	return text
end

local function exists(path)
	local file = io.open(path, "r")
	if file then file:close() end
	return file ~= nil
end

-- A plist string value by key.
local function plistString(text, key)
	return text:match("<key>" .. key .. "</key>%s*<string>(.-)</string>")
end

-- Files under an app that are not read at run time: docs, the project and
-- its Xcode data, signing, App Store and website material, sources of
-- generated images, and build output.
local NOT_RUNTIME = {md = true, plist = true, pbxproj = true, xcscheme = true, entitlements = true, sh = true,
	svg = true, json = true, png = true}
local SKIP_DIRS = {"%.xcodeproj/", "%.xcassets/", "/Build/", "/ci_scripts/", "/store%-assets/"}

local function runtimeExtensions(dir)
	local found = {}
	local list = assert(io.popen("find " .. dir .. " -type f"))
	for path in list:lines() do
		local skipped = false
		for _, pattern in ipairs(SKIP_DIRS) do
			if path:find(pattern) then skipped = true end
		end
		local ext = path:match("%.([%w]+)$")
		if not skipped and ext and not NOT_RUNTIME[ext] then found[ext] = path end
	end
	list:close()
	return found
end

-- Mirrors the case in scripts/release/release.sh.
local RELEASES = {diskmap = "Diskmap", dnb = "DrumAndBass"}

local script = read("scripts/release/release.sh")
local workflow = read(".github/workflows/release.yml")
for app, product in pairs(RELEASES) do
	t.expect(script:find(app .. ") product=" .. product, 1, true) ~= nil, app .. ": the release script builds " .. product)
	t.expect(workflow:find('"' .. app .. '/*"', 1, true) ~= nil, app .. ": its tags start the release workflow")

	local dir = "apps/" .. app
	local plist = read(dir .. "/Info.plist")
	t.assertEqual(plistString(plist, "CFBundleExecutable"), product, app .. ": the executable is the product")
	local entry = plistString(plist, "LuaObjCEntry")
	t.assertEqual(entry, dir .. "/init.lua", app .. ": Info.plist names its entry point for the launcher")
	t.expect(exists(entry), app .. ": the entry point exists")

	local project = read(dir .. "/" .. product .. ".xcodeproj/project.pbxproj")
	t.expect(project:find("path = ../../scripts/launcher;", 1, true) ~= nil, app .. ": runs the shared launcher")
	t.expect(exists(dir .. "/" .. product .. ".xcodeproj/xcshareddata/xcschemes/" .. product .. ".xcscheme"),
		app .. ": has a shared scheme to archive")
	t.expect(project:find("copy apps/" .. app .. " apps/" .. app, 1, true) ~= nil, app .. ": copies its own tree")
	t.expect(project:find("ENABLE_HARDENED_RUNTIME = YES;", 1, true) ~= nil, app .. ": hardened runtime, for notarizing")
	local copied = {}
	for ext in project:gmatch("%-%-include='%*%.(%w+)'") do copied[ext] = true end
	for ext, example in pairs(runtimeExtensions(dir)) do
		t.expect(copied[ext], app .. ": the bundle copies ." .. ext .. " files such as " .. example)
	end
end
t.expect(not exists("scripts/diskmap/launcher.c"), "one launcher, shared by every bundled app")
-- A run without signing secrets never publishes, so it cannot replace a DMG
-- signed and notarized on a Mac.
t.expect(workflow:find("if: steps.signing.outputs.unsigned == '0'\n        env:\n          GH_TOKEN", 1, true) ~= nil,
	"the workflow publishes only signed builds")

t.summary()
