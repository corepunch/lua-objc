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

-- Xcode rewrites the file in its own layout whenever it saves, so compare
-- structure only: drop comments and collapse whitespace.
local pbxproj = read(PROJECT .. "/project.pbxproj")
	:gsub("/%*.-%*/", "")
	:gsub("%s+", " ")

-- Synchronized folders replace per-file references: no source file is listed,
-- so adding a .m or .lua file needs no project edit.
t.expect(pbxproj:find("objectVersion = 77;", 1, true) ~= nil, "project uses synchronized folders")
t.expect(pbxproj:find("lastKnownFileType = sourcecode", 1, true) == nil, "no per-file source references")

-- A synchronized folder that contains the .xcodeproj makes Xcode add the
-- project as a subproject of itself; the app folder uses a plain group.
t.expect(pbxproj:find("wrapper.pb-project", 1, true) == nil, "project does not reference itself")
t.expect(pbxproj:find("projectReferences", 1, true) == nil, "project has no subprojects")
for path in pbxproj:gmatch("isa = PBXFileSystemSynchronizedRootGroup;.-path = \"?([^;\"]+)\"?;") do
	t.expect(path ~= "." and path ~= "../diskmap", "synchronized folder excludes the project: " .. path)
end

-- Every exception set names files that exist in its synchronized folder, so
-- a renamed unity root or plugin fails here instead of in xcodebuild.
local folders = {}
for body in pbxproj:gmatch("isa = PBXFileSystemSynchronizedRootGroup; (.-) };") do
	local path = body:match("path = \"?([^;\"]+)\"?;")
	for exception in (body:match("exceptions = %((.-)%)") or ""):gmatch("(%x+)") do
		folders[exception] = path
	end
end
local checked = 0
for id, files in pbxproj:gmatch("(%x+) = { isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = %((.-)%);") do
	local folder = assert(folders[id], "exception set belongs to a folder: " .. id)
	for name in files:gmatch("([^,%s]+),") do
		t.expect(exists("apps/diskmap/" .. folder .. "/" .. name), "exception file exists: " .. folder .. "/" .. name)
		checked = checked + 1
	end
end
t.expect(checked >= 6, "exception sets were parsed")
t.expect(pbxproj:find("membershipExceptions = ( embedded_lua_module.c, main.m, );", 1, true) ~= nil,
	"AppKit compiles only the unity roots from src")

-- One Run Script copies the Lua trees in bulk; a stale Xcode Build folder
-- beside the project must never be copied into the bundle.
local script = assert(pbxproj:match('name = "Copy Lua";.-shellScript = "(.-)";'))
t.expect(script:find("copy lua lua", 1, true) ~= nil, "copies framework Lua")
t.expect(script:find("copy apps/diskmap apps/diskmap", 1, true) ~= nil, "copies Diskmap Lua")
t.expect(script:find("--exclude=Build/", 1, true) ~= nil, "skips Xcode Build folders")
t.expect(pbxproj:find("ENABLE_USER_SCRIPT_SANDBOXING = NO;", 1, true) ~= nil, "script may read the source tree")

-- App Store Connect symbolicates crashes with the archive's dSYMs.
t.expect(pbxproj:find('DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; ENABLE_USER_SCRIPT_SANDBOXING = NO; GCC_PREPROCESSOR_DEFINITIONS = LUA_USE_MACOSX; HEADER_SEARCH_PATHS = "$(PROJECT_DIR)/../../vendor/lua-5.4.8/src"; MACOSX_DEPLOYMENT_TARGET = 26.0; OBJROOT = "$(PROJECT_DIR)/../../build/xcode-project/Intermediates"; SDKROOT = macosx; SYMROOT = "$(PROJECT_DIR)/../../build/xcode-project/Products"; }; name = Release;', 1, true) ~= nil,
	"Release builds emit dSYMs for every target")

-- The launcher is plain C and only dlopens AppKit.dylib later. Inside the App
-- Sandbox, LaunchServices receives its launchservicesd lookup extension only
-- when it is loaded at process start, so the launcher must link CoreServices
-- itself or +[NSApplication sharedApplication] aborts on every Finder launch.
local sandboxed, linkedCoreServices = 0, 0
for settings in pbxproj:gmatch("buildSettings = {(.-)};") do
	if settings:find("PRODUCT_NAME = Diskmap;", 1, true) then
		sandboxed = sandboxed + 1
		if settings:find('OTHER_LDFLAGS = "-Wl,-needed_framework,CoreServices";', 1, true) then
			linkedCoreServices = linkedCoreServices + 1
		end
	end
end
t.expect(sandboxed == 2, "app target has Debug and Release configurations")
t.expect(linkedCoreServices == sandboxed, "sandboxed launcher links CoreServices at load time")

local appTarget = assert(pbxproj:match("(%x+) = { isa = PBXNativeTarget; [^}]-name = Diskmap;"))
local scheme = read(PROJECT .. "/xcshareddata/xcschemes/Diskmap.xcscheme")
-- Xcode reformats the scheme as `BlueprintIdentifier = "..."` when it saves.
t.expect(scheme:find('BlueprintIdentifier%s*=%s*"' .. appTarget .. '"') ~= nil, "scheme builds the app target")

os.exit(t.summary() and 0 or 1)
