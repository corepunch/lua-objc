-- Every fixed folder name the app's code itself relies on, in one place:
-- what a scan skips, what a cleanup may never touch, what the worktree
-- search does not descend into. `knowledge/Filesystem` describes the
-- locations a person browses; this file holds the paths that rules and
-- walks compare against. Paths starting with "/" under `home` are relative
-- to the home folder; the rest are absolute.
local Paths = {}

-- Never walked by a scan: other volumes, devices and the system volumes.
Paths.scanExclusions = {"/Volumes", "/dev", "/System/Volumes"}

-- Walked by neither a scan nor a size total unless "include media" is on:
-- the Photos and Music libraries and their containers.
Paths.mediaLibraries = {
	"/Library/Photos", "/Library/Music", "/Library/MediaLibrary",
	"/Library/Containers/com.apple.Photos", "/Library/Containers/com.apple.Music",
	"/Library/Containers/com.apple.AMPArtworkAgent",
	"/Library/Group Containers/group.com.apple.Photos", "/Library/Group Containers/group.com.apple.Music",
}

-- The roots a mock snapshot of the startup disk is exported from.
Paths.snapshotRoots = {
	"/", "/Users", "/Applications", "/Library", "/private", "/opt", "/usr/local",
	"/System/Volumes/Data", "/System/Volumes/Preboot", "/System/Volumes/Recovery",
	"/System/Volumes/Update", "/System/Volumes/xarts", "/System/Volumes/Hardware", "/System/Volumes/iSCPreboot",
}

-- The startup disk's files live on this Data volume, joined to "/" by firmlinks.
Paths.startupData = "/System/Volumes/Data"

-- Locations that are never cleanup targets themselves, however they were
-- marked: the disk, system folders and mount points. Items inside are allowed.
Paths.refused = {"/", "/System", "/Library", "/Applications", "/Users", "/Volumes", "/private", "/usr", "/bin",
	"/sbin", "/opt", "/cores", "/nix", "/Network", "/Users/Shared", "/Library/Application Support", "/Library/Caches",
	"/private/etc", "/private/tmp", "/private/var", "/private/var/folders", "/private/var/tmp", "/private/var/vm",
	"/private/var/log", "/private/var/db", "/usr/local", "/opt/homebrew"}

-- Nothing at or below these moves.
Paths.protected = {"/System", "/Library/Keychains"}

-- Home folder and its standard folders: never cleanup targets themselves.
Paths.homeFolders = {"", "/Library", "/Desktop", "/Documents", "/Downloads", "/Developer", "/Movies", "/Music",
	"/Pictures", "/Public", "/Applications", "/.Trash", "/Library/Caches", "/Library/Application Support",
	"/Library/Containers", "/Library/Group Containers", "/Library/Developer", "/Library/Developer/Xcode",
	"/Library/Mobile Documents", "/Library/CloudStorage", "/Library/Logs", "/Library/Saved Application State",
	"/Library/Application Scripts", "/Library/Fonts", "/Library/HTTPStorages", "/Library/WebKit"}

-- Credentials, accounts, settings, and the mail and message stores, which
-- only their apps can change safely. Nothing at or below these moves.
Paths.homeProtected = {"/Library/Keychains", "/Library/Preferences", "/Library/Mail", "/Library/Messages",
	"/Library/Accounts", "/Library/Cookies", "/Library/Passes", "/Library/IdentityServices", "/.ssh", "/.gnupg"}

-- Each folder directly inside these is one app's or provider's whole cloud
-- store; removing it removes the documents from every device.
Paths.cloudRoots = {"/Library/Mobile Documents", "/Library/CloudStorage"}

-- Root links into /private.
Paths.aliases = {"/tmp", "/var", "/etc"}

-- Media libraries are packages their app manages; items are removed in the
-- app, never by moving the library. Keys are lower-case extensions.
Paths.libraryPackages = {photoslibrary = true, photolibrary = true, migratedphotolibrary = true, aplibrary = true,
	musiclibrary = true, tvlibrary = true, imovielibrary = true}

-- Folder names the repository search does not descend into.
Paths.repositoryPrune = {"node_modules", ".Trash", "Pods", ".build", "target", ".venv", "venv", "DerivedData", ".cache", ".npm"}

return Paths
