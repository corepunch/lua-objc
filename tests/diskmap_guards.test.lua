_G.__headless = true
local t = require("TestKit")
local Paths = require("apps.diskmap.helpers.Paths")
local Verify = require("apps.diskmap.helpers.Verify")
local Remove = require("apps.diskmap.flows.Remove")
local Store = require("apps.diskmap.Store")

-- The path guards: what may never be a cleanup target, whatever listed it.
local home = "/Users/test"
Store.new(home)
local refused = {
	{"/", "the disk"}, {"/System", "the system"}, {"/Library", "the shared Library"}, {"/Applications", "Applications"},
	{"/Users", "Users"}, {"/private/var", "var"}, {"/private/tmp", "tmp itself"}, {"/tmp", "tmp through its link"},
	{"/Volumes/External", "a mount point"}, {"/System/Volumes/Data", "a system volume"},
	{home, "the home folder"}, {home .. "/Library", "the home Library"}, {home .. "/Documents", "Documents"},
	{home .. "/Library/Caches", "the Caches folder itself"}, {home .. "/Library/Developer/Xcode", "Xcode's folder itself"},
	{home .. "/Library/Keychains/login.keychain-db", "a keychain"}, {home .. "/Library/Preferences/com.x.plist", "a preference"},
	{home .. "/Library/Mail/V10", "mail"}, {home .. "/.ssh/id_ed25519", "ssh keys"},
	{home .. "/Library/Mobile Documents/com~apple~CloudDocs", "a cloud root"},
	{"/Users/other/Downloads/x", "another user's files"}, {home .. "/Pictures/Photos Library.photoslibrary", "a media library"},
	{"/System/Library/Caches/x", "anything under /System"}, {"/Library/Keychains/x", "the shared keychains"},
	{home .. "/DOCUMENTS", "a standard folder in another case"},
}
for _, case in ipairs(refused) do
	local ok, why = Paths.validate(case[1], home)
	t.expect(not ok and type(why) == "string", "never removes " .. case[2] .. " (" .. case[1] .. ")")
end
local allowed = {
	home .. "/Library/Caches/com.example.app", home .. "/Library/Developer/Xcode/DerivedData/App-abc",
	home .. "/Developer/site/node_modules", home .. "/Downloads/big.iso", "/Volumes/External/old", home .. "/.codex/sessions",
	"/private/tmp/scratch", "/Users/Shared/old",
}
for _, path in ipairs(allowed) do
	t.expect(Paths.validate(path, home), "may remove " .. path)
end
t.expect(not Paths.validateReview("relative"), "a path must be absolute")
t.expect(not Paths.validateReview("/a/../b") and not Paths.validateReview("/a//b"), "and canonical")
t.assertEqual(Paths.normalize("/tmp/x/"), "/private/tmp/x", "paths are compared through root links, without trailing slashes")
t.assertEqual(Paths.normalize("/Users/Test/DOCS"), "/users/test/docs", "and without regard to case")
t.expect(Paths.within("/a/b", "/a") and not Paths.within("/ab", "/a") and Paths.within("/x", "/"), "within is by path component")

-- The hard guard behind every move, whatever the knowledge says.
for _, path in ipairs({"/System/x", "/usr/bin/x", "/private/var/db/x", "/Library/Apple/x", "/bin/sh"}) do
	local ok, why = Verify.check({path = path}, home, {})
	t.expect(not ok and why.code == "protected", path .. " is protected from every move")
end
t.expect(Verify.check({path = home .. "/Library/Caches/com.example.app"}, home, {}), "an app cache moves")

-- What a row must be before Diskmap offers to remove it.
local row = {id = "x", path = home .. "/Library/Caches/com.example.app", state = "measured", verdict = "safe", action = "trash", name = "x"}
t.expect(Remove.allowed(row), "a measured, safe, removable row is offered")
t.expect(not Remove.allowed({path = row.path, state = "denied", verdict = "safe", action = "trash"}), "an unmeasured row is not")
t.expect(not Remove.allowed({path = row.path, state = "measured", verdict = "system", action = "none"}), "a system row is not")
local ok, why = Remove.allowed({path = row.path, state = "measured", verdict = "safe", action = "none", admin = true})
t.expect(not ok and why:find("administrator", 1, true), "a root-owned row says Finder needs an administrator")
ok, why = Remove.allowed({path = home .. "/Documents", state = "measured", verdict = "review", action = "trash"})
t.expect(not ok and why == "Standard folder in your home.", "the path guards apply to every trash row")
t.expect(Remove.allowed({id = "runtime:x", path = "/Library/Developer/CoreSimulator/Volumes/x", runtimeId = "x", state = "measured", verdict = "safe", action = "runtimeDelete"}), "simctl rows are not held to the path guards")

os.exit(t.summary() and 0 or 1)
