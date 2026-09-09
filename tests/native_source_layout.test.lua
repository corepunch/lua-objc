_G.__headless = true

local t = require("TestKit")
local bridge = require("AppKitNative")

local function read(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("*a")
	file:close()
	return source
end

-- Guard the folder contract without enumerating classes: adding a native
-- implementation must not bring back a separate header for every class.
local function checkFolder(path)
	local headers = {}
	local implementations = {}
	for _, entry in ipairs(assert(bridge._listDirectory(path))) do
		if entry.directory then
			checkFolder(entry.path)
		elseif entry.name:match("%.h$") then
			headers[#headers + 1] = entry.name
		elseif entry.name:match("%.m$") then
			implementations[#implementations + 1] = entry.path
		end
	end
	if #implementations == 0 then return end
	t.expect(#headers <= 1, path .. " has at most one shared native header")
	if path ~= "ios/LuaRuntime" then return end
	t.assertEqual(#headers, 1, "independently compiled host files share one header")
	for _, implementation in ipairs(implementations) do
		local source = read(implementation)
		t.expect(source:find('#import "' .. headers[1] .. '"', 1, true) ~= nil,
			implementation .. " uses the shared host declarations")
		for imported in source:gmatch('#import%s+"([^"]+)"') do
			local file = io.open(path .. "/" .. imported, "r")
			t.expect(file ~= nil, implementation .. " imports an existing local file")
			if file then file:close() end
		end
	end

	-- Header-only edits must invalidate the executable, not just .m changes.
	local makefile = read("Makefile"):gsub("\\\n", " ")
	local dependencies = makefile:match("%$%(HOST_BINARY%):([^\n]+)") or ""
	t.expect(dependencies:find(path .. "/" .. headers[1], 1, true) ~= nil,
		"host executable tracks its shared header as a build dependency")
end

checkFolder("src")
checkFolder("ios")

-- UIKit resolves scene delegates and executables from bundle metadata, so a
-- class/file rename must update the launch contract as well as compile.
local runtimePath = "ios/LuaRuntime/"
local header = read(runtimePath .. "LuaRuntime.h")
local plist = read(runtimePath .. "Info.plist")
local sceneClass = assert(plist:match(
	"<key>UISceneDelegateClassName</key>%s*<string>([^<]+)</string>"))
local executable = assert(plist:match(
	"<key>CFBundleExecutable</key>%s*<string>([^<]+)</string>"))
t.expect(header:find("@interface " .. sceneClass .. " :", 1, true) ~= nil,
	"bundle scene delegate names a declared runtime class")
t.expect(read(runtimePath .. sceneClass .. ".m"):find(
	"@implementation " .. sceneClass, 1, true) ~= nil,
	"bundle scene delegate has a matching implementation")
t.expect(read(runtimePath .. "main.m"):find(
	"NSStringFromClass(LRTApplicationDelegate.class)", 1, true) ~= nil,
	"application delegate is resolved from its compiled class")
t.expect(read("Makefile"):find("HOST_BINARY := $(HOST_BUNDLE)/" .. executable,
	1, true) ~= nil, "bundle executable matches the build output")
t.expect(read("scripts/ios-run.sh"):find("/build/ios/" .. executable .. ".app",
	1, true) ~= nil, "launcher installs the renamed runtime bundle")
for class in header:gmatch("@interface%s+(%w+)") do
	t.expect(class:match("^LRT") ~= nil, "runtime class uses the LRT namespace: " .. class)
	t.expect(read(runtimePath .. class .. ".m"):find("@implementation " .. class,
		1, true) ~= nil, "class and implementation filename agree: " .. class)
end

os.exit(t.summary() and 0 or 1)
