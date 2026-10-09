_G.__headless = true
local Paths = require("apps.diskmap.helpers.Paths")
local Locations = require("apps.diskmap.models.Locations")
local t = require("TestKit")
local Verify = require("apps.diskmap.helpers.Verify")
local Store = require("apps.diskmap.Store")

-- The collector and the Review sheet refuse anything whose loss a person
-- could not undo from the Trash alone (#59): credentials, mail and message
-- stores, cloud roots, media libraries, other people's homes and system
-- folders, under any spelling the file system accepts.
local home = "/Users/test"
local refused = {
	{home .. "/Library/Keychains", "the keychain folder"},
	{home .. "/Library/Keychains/login.keychain-db", "a keychain"},
	{"/Library/Keychains", "the system keychain folder"},
	{"/Library/Keychains/System.keychain", "the system keychain"},
	{home .. "/Library/Preferences", "preferences"},
	{home .. "/Library/Preferences/com.apple.finder.plist", "a preference file"},
	{home .. "/Library/Mobile Documents", "the iCloud Drive root"},
	{home .. "/Library/Mobile Documents/com~apple~CloudDocs", "the iCloud Drive folder"},
	{home .. "/Library/CloudStorage", "the cloud storage root"},
	{home .. "/Library/CloudStorage/Dropbox", "a cloud provider's folder"},
	{home .. "/Library/Mail", "mailboxes"},
	{home .. "/Library/Mail/V10/MailData", "mail data"},
	{home .. "/Library/Messages", "message history"},
	{home .. "/Library/Messages/chat.db", "the message database"},
	{home .. "/Library/Accounts", "accounts"},
	{home .. "/Library/Cookies", "cookies"},
	{home .. "/.ssh", "SSH keys"},
	{home .. "/.ssh/id_ed25519", "an SSH key"},
	{home .. "/Pictures/Photos Library.photoslibrary", "the Photos library"},
	{home .. "/Music/Music/Music Library.musiclibrary", "the Music library"},
	{"/Volumes/Media/Archive.photoslibrary", "a Photos library on another disk"},
	{"/Users/Shared", "the shared folder"},
	{"/Users/other", "another user's home"},
	{"/Users/other/Documents/taxes.pdf", "another user's file"},
	{"/Users/testing", "a home whose name starts like mine"},
	{"/tmp", "/tmp"},
	{"/private/tmp", "/private/tmp"},
	{"/var", "/var"},
	{"/private/var", "/private/var"},
	{"/private/var/folders", "the temporary items root"},
	{"/var/folders", "the temporary items root through /var"},
	{"/etc", "/etc"},
	{home .. "/DOCUMENTS", "a standard folder in capitals"},
	{"/users/TEST/documents", "a standard folder in another case"},
	{"/users/test", "the home folder in lower case"},
	{"/SYSTEM/Library/Caches", "a system folder in capitals"},
	{"/applications", "Applications in lower case"},
	{home .. "/library/keychains", "keychains in lower case"},
	{home .. "/Documents/", "a standard folder with a trailing slash"},
	{home .. "/Documents/./", "a path with a dot segment"},
	{home .. "/Downloads/../Documents", "a path with a parent segment"},
	{"/Volumes/Backup", "a mount point"},
	{"/volumes/backup", "a mount point in lower case"},
}
for _, case in ipairs(refused) do
	t.expect(not Paths.validate(case[1], home), "the collector refuses " .. case[2])
	local ok, why = Verify.check({path = case[1]}, nil, home, {})
	t.expect(not ok and (why.code == "location" or why.code == "protected"), "the Review sheet refuses " .. case[2])
end
local reason = select(2, Paths.validate(home .. "/Library/Keychains", home))
t.expect(reason:find("Passwords", 1, true) ~= nil, "a refusal says why")

local allowed = {
	home .. "/Downloads/installer.dmg",
	home .. "/downloads/Installer.DMG",
	home .. "/Library/Caches/com.example.app",
	home .. "/Library/Developer/Xcode/DerivedData",
	home .. "/Library/Developer/Xcode/DerivedData/App-abc",
	home .. "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
	home .. "/Library/Mobile Documents/com~apple~CloudDocs/Archive/old.zip",
	home .. "/Library/CloudStorage/Dropbox/big.mov",
	home .. "/Documents/site/node_modules",
	home .. "/Pictures/export.photoslibrary.zip",
	home .. "/Movies/Holiday.mov",
	"/Applications/Old.app",
	"/Users/Shared/Installers/old.pkg",
	"/private/tmp/build-output",
	"/tmp/build-output",
	"/Volumes/Media/Footage/clip.mov",
}
for _, path in ipairs(allowed) do
	local ok, why = Paths.validate(path, home)
	t.expect(ok, "the collector takes " .. path .. (why and (": " .. why) or ""))
	t.expect(Verify.check({path = path}, nil, home, {}), "the Review sheet moves " .. path)
end

-- Guards never outlaw what the catalog itself offers to move to the Trash.
local model = Store.new(home)
local offered = 0
for _, row in ipairs(Locations:leaves()) do
	if row.action == "trash" and row.path then
		offered = offered + 1
		local ok, why = Paths.validate(row.path, home)
		t.expect(ok, "catalog item " .. row.id .. " can be marked" .. (why and (": " .. why) or ""))
	end
end
t.expect(offered > 5, "the catalog offers locations to check")

t.assertEqual(Paths.normalize("/tmp/x/"), "/private/tmp/x", "normalizing follows the root's links")
t.assertEqual(Paths.normalize("/"), "/", "the root stays the root")
t.assertEqual(Paths.normalize("/tmpfiles"), "/tmpfiles", "a name that starts like a link is left alone")

-- The same guard is the marks table's constraint: a row that breaks it is
-- never stored, and a mark answers the location it stands for.
local Marks = require("apps.diskmap.models.Marks")
local stored, refusal = Marks:create({path = "/System"})
t.expect(stored ~= nil, "system locations can be flagged for inspection")
t.expect(not Verify.check(stored, nil, home, {}), "flagging system storage never authorizes deletion")
Marks:clear()
local derived = Locations:find("derived")
t.expect(Marks:add({path = derived.path, resourceId = "derived"}), "a location can be marked")
t.expect(Marks:find(derived.path):location() == derived, "a mark answers its location")
t.expect(Marks:add({path = home .. "/Downloads/a.zip"}) and Marks:find(home .. "/Downloads/a.zip"):location() == nil, "a mark of a plain file has none")
Marks:clear()

os.exit(t.summary() and 0 or 1)
