local Paths = {}
local Knowledge = require("apps.diskmap.knowledge.Paths")

-- The folder lists are data in knowledge/Paths. Every comparison is made
-- on `Paths.normalize`d paths: APFS is case-insensitive by default, so
-- ~/DOCUMENTS is ~/Documents, and /tmp is a link to /private/tmp.
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
	for _, alias in ipairs(Knowledge.aliases) do
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
	for _, refused in ipairs(lowered(Knowledge.refused)) do
		if key == refused then return false, "System location." end
	end
	if key:match("^/volumes/[^/]+$") or key:match("^/system/volumes/[^/]+$") then return false, "Mount point." end
	for _, folder in ipairs(lowered(Knowledge.protected)) do
		if Paths.within(key, folder) then return false, "Protected macOS location." end
	end
	for _, folder in ipairs(lowered(Knowledge.homeFolders, home)) do
		if key == folder then return false, "Standard folder in your home." end
	end
	for _, folder in ipairs(lowered(Knowledge.homeProtected, home)) do
		if Paths.within(key, folder) then return false, "Passwords, accounts, settings and messages are managed by their apps." end
	end
	for _, folder in ipairs(lowered(Knowledge.cloudRoots, home)) do
		if key:sub(1, #folder + 1) == folder .. "/" and not key:sub(#folder + 2):find("/", 1, true) then
			return false, "Cloud storage root."
		end
	end
	local user = key:match("^/users/([^/]+)")
	if user and user ~= "shared" and not Paths.within(key, home) then return false, "Another user's home folder." end
	local extension = key:match("%.([^./]+)$")
	if extension and Knowledge.libraryPackages[extension] then return false, "Media library. Remove items in its app." end
	return true
end

return Paths
