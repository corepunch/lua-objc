_G.__headless = true
local t = require("TestKit")

local PROJECT = "apps/diskmap/Diskmap.xcodeproj"

local function read(path)
	local file = assert(io.open(path, "r"))
	local text = file:read("*a")
	file:close()
	return text
end

local function exists(path)
	local file = io.open(path, "r")
	if file then file:close() end
	return file ~= nil
end

local pbxproj = read(PROJECT .. "/project.pbxproj")

-- Synchronized folders replace per-file references: only the three products
-- are explicit file references, so adding a .m or .lua file needs no edit.
t.expect(pbxproj:find("objectVersion = 77;", 1, true) ~= nil, "project uses synchronized folders")
local references = 0
for _ in pbxproj:gmatch("isa = PBXFileReference;") do references = references + 1 end
t.assertEqual(references, 3, "only product file references")

-- Every exception set names files that exist in its synchronized folder, so
-- a renamed unity root or plugin fails here instead of in xcodebuild.
local folders = {}
for id, body in pbxproj:gmatch("(%x+) /%*[^*]*%*/ = {isa = PBXFileSystemSynchronizedRootGroup;(.-)};") do
	for exception in (body:match("exceptions = %((.-)%)") or ""):gmatch("(%x+)") do
		folders[exception] = body:match("path = \"?([^;\"]+)\"?;")
	end
end
local checked = 0
for id, files in pbxproj:gmatch("(%x+) /%*[^*]*%*/ = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = %((.-)%);") do
	local folder = assert(folders[id], "exception set belongs to a folder: " .. id)
	for name in files:gmatch("([^,%s]+),") do
		t.expect(exists("apps/diskmap/" .. folder .. "/" .. name), "exception file exists: " .. folder .. "/" .. name)
		checked = checked + 1
	end
end
t.expect(checked >= 8, "exception sets were parsed")
t.expect(pbxproj:find("membershipExceptions = (main.m, embedded_lua_module.c, );", 1, true) ~= nil,
	"AppKit compiles only the unity roots from src")

-- One Run Script copies the Lua trees in bulk; a stale Xcode Build folder
-- beside the project must never be copied into the bundle.
local script = assert(pbxproj:match('name = "Copy Lua";.-shellScript = "(.-)";'))
t.expect(script:find("copy lua lua", 1, true) ~= nil, "copies framework Lua")
t.expect(script:find("copy apps/diskmap apps/diskmap", 1, true) ~= nil, "copies Diskmap Lua")
t.expect(script:find("--exclude=Build/", 1, true) ~= nil, "skips Xcode Build folders")
t.expect(pbxproj:find("ENABLE_USER_SCRIPT_SANDBOXING = NO;", 1, true) ~= nil, "script may read the source tree")

local appTarget = assert(pbxproj:match("(%x+) /%* Diskmap %*/ = {\n\t\t\tisa = PBXNativeTarget;"))
local scheme = read(PROJECT .. "/xcshareddata/xcschemes/Diskmap.xcscheme")
t.expect(scheme:find('BlueprintIdentifier="' .. appTarget .. '"', 1, true) ~= nil, "scheme builds the app target")

os.exit(t.summary() and 0 or 1)
