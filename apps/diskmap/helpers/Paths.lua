local Paths = {}

-- Locations that are never cleanup targets themselves, however they were
-- marked: the disk, system folders, the home folder and its standard folders,
-- and mount points. Items inside them are allowed. Every comparison is made
-- on `Paths.normalize`d paths: APFS is case-insensitive by default, so
-- ~/DOCUMENTS is ~/Documents, and /tmp is a link to /private/tmp.
local REFUSED = {"/", "/System", "/Library", "/Applications", "/Users", "/Volumes", "/private", "/usr", "/bin",
	"/sbin", "/opt", "/cores", "/nix", "/Network", "/Users/Shared", "/Library/Application Support", "/Library/Caches",
	"/private/etc", "/private/tmp", "/private/var", "/private/var/folders", "/private/var/tmp", "/private/var/vm",
	"/private/var/log", "/private/var/db", "/usr/local", "/opt/homebrew"}
local HOME_FOLDERS = {"", "/Library", "/Desktop", "/Documents", "/Downloads", "/Developer", "/Movies", "/Music",
	"/Pictures", "/Public", "/Applications", "/.Trash", "/Library/Caches", "/Library/Application Support",
	"/Library/Containers", "/Library/Group Containers", "/Library/Developer", "/Library/Developer/Xcode",
	"/Library/Mobile Documents", "/Library/CloudStorage", "/Library/Logs", "/Library/Saved Application State",
	"/Library/Application Scripts", "/Library/Fonts", "/Library/HTTPStorages", "/Library/WebKit"}
-- Nothing at or below these moves: credentials, accounts, settings, and the
-- mail and message stores, which only their apps can change safely.
local HOME_PROTECTED = {"/Library/Keychains", "/Library/Preferences", "/Library/Mail", "/Library/Messages",
	"/Library/Accounts", "/Library/Cookies", "/Library/Passes", "/Library/IdentityServices", "/.ssh", "/.gnupg"}
local PROTECTED = {"/System", "/Library/Keychains"}
-- Each folder directly inside these is one app's or provider's whole cloud
-- store; removing it removes the documents from every device.
local CLOUD_ROOTS = {"/Library/Mobile Documents", "/Library/CloudStorage"}
-- Media libraries are packages their app manages; items are removed in the
-- app, never by moving the library.
local LIBRARY_PACKAGES = {photoslibrary = true, photolibrary = true, migratedphotolibrary = true, aplibrary = true,
	musiclibrary = true, tvlibrary = true, imovielibrary = true}
local ALIASES = {"/tmp", "/var", "/etc"}

local function lowered(list, prefix)
	local result = {}
	for _, path in ipairs(list) do table.insert(result, ((prefix or "") .. path):lower()) end
	return result
end

function Paths.within(path, folder) return path == folder or path:sub(1, #folder + 1) == folder .. "/" end

-- The path as the guards compare it: without trailing slashes, through the
-- root's links to /private, and in lower case.
function Paths.normalize(path)
	local trimmed = path:gsub("/+$", "")
	if trimmed == "" then return "/" end
	trimmed = trimmed:lower()
	for _, alias in ipairs(ALIASES) do
		if Paths.within(trimmed, alias) then return "/private" .. trimmed end
	end
	return trimmed
end

-- Checks a path is something a person could mean to throw away. Returns ok
-- and a reason for refusal.
function Paths.validate(path, home)
	if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return false, "Not an absolute path." end
	if path:find("/%.%./") or path:find("/%.%.$") or path:find("/%./") or path:find("/%.$") or path:find("//", 1, true) then
		return false, "The path is not canonical."
	end
	local key = Paths.normalize(path)
	home = Paths.normalize(home or "")
	if home == "/" then home = "" end
	for _, refused in ipairs(lowered(REFUSED)) do
		if key == refused then return false, "System location." end
	end
	if key:match("^/volumes/[^/]+$") or key:match("^/system/volumes/[^/]+$") then return false, "Mount point." end
	for _, folder in ipairs(lowered(PROTECTED)) do
		if Paths.within(key, folder) then return false, "Protected macOS location." end
	end
	for _, folder in ipairs(lowered(HOME_FOLDERS, home)) do
		if key == folder then return false, "Standard folder in your home." end
	end
	for _, folder in ipairs(lowered(HOME_PROTECTED, home)) do
		if Paths.within(key, folder) then return false, "Passwords, accounts, settings and messages are managed by their apps." end
	end
	for _, folder in ipairs(lowered(CLOUD_ROOTS, home)) do
		if key:sub(1, #folder + 1) == folder .. "/" and not key:sub(#folder + 2):find("/", 1, true) then
			return false, "Cloud storage root."
		end
	end
	local user = key:match("^/users/([^/]+)")
	if user and user ~= "shared" and not Paths.within(key, home) then return false, "Another user's home folder." end
	local extension = key:match("%.([^./]+)$")
	if extension and LIBRARY_PACKAGES[extension] then return false, "Media library. Remove items in its app." end
	return true
end

return Paths
