local Map = require("apps.diskmap.knowledge.Filesystem")
local Library = require("apps.diskmap.knowledge.Library")
local Leftovers = require("apps.diskmap.helpers.Leftovers")

-- What a folder or file is and who it belongs to, for any path a person
-- browses: the answer to "what is this, and may it go?". In order:
--
-- 1. a location knowledge/Filesystem describes by its exact path;
-- 2. a name that means the same anywhere (knowledge/Library `names`);
-- 3. a child of a Library folder whose children are one per app
--    (knowledge/Library `parents`), named after the app it belongs to, found
--    among the installed apps (helpers/Leftovers `owner`) or Apple's
--    services; the inside of an app's sandbox mirrors ~/Library;
-- 4. anything else inside a sandbox belongs to the sandbox's app.
--
-- `facts` are what the caller knows: `home`, `apps` (Leftovers.index of the
-- installed apps, nil until Spotlight answers; then nothing is called
-- unclaimed) and `container(path)`, the bundle identifier the container
-- metadata names for a folder named by a random UUID, or nil.
-- Answers {owner, kind, what, unclaimed} or nil.
local Explain = {}

local function tilde(path, home)
	if home and home ~= "" and (path == home or path:sub(1, #home + 1) == home .. "/") then return "~" .. path:sub(#home + 1) end
	return path
end

local function fill(text, owner)
	return (text:gsub("%%s", (owner:gsub("%%", "%%%%"))))
end

-- "A", "A and B", "A, B and 2 more".
function Explain.names(list)
	if #list == 1 then return list[1] end
	if #list == 2 then return list[1] .. " and " .. list[2] end
	return list[1] .. ", " .. list[2] .. " and " .. (#list - 2) .. " more"
end

-- The macOS feature behind an Apple identifier such as "com.apple.bird" or
-- "group.com.apple.CloudDocs": its service name, or macOS.
local function apple(id)
	local rest = id:lower():match("^com%.apple%.(.+)$") or id:lower():match("^apple%.(.+)$")
	if not rest then return nil end
	for part in rest:gmatch("[^%.]+") do
		if Library.services[part] then return Library.services[part] end
	end
	return "macOS"
end

-- Who the item `name` in a per-app folder belongs to, as a display name.
local function ownerOf(name, rule, facts, path)
	local id = Leftovers.identifier((name:gsub("%.plist$", "")))
	if not id and name:match("^%x+%-%x+%-%x+%-%x+%-%x+$") and facts.container then
		id = facts.container(path)
		if id then name = id end
	end
	local installed = facts.apps and Leftovers.owner(name, facts.apps, rule.byName)
	if installed then -- The sentence for the packages an installer receipt names
-- (`pkgutil --file-info` lists each as "pkgid: com.example.pkg"), or nil.
function Explain.packages(output)
	local ids = {}
	for id in (output or ""):gmatch("pkgid: ([^\n]+)") do table.insert(ids, id) end
	return ids
end
function Explain.package(ids)
	if not ids or #ids == 0 then return nil end
	if #ids == 1 then return "Installed by the package " .. ids[1] .. "." end
	return "Installed by the package " .. ids[1] .. " and " .. (#ids - 1) .. " more."
end

return Explain.names(installed) end
	local service = id and apple(id) or Library.services[name:lower()]
	if service then return service end
	return nil
end

local function byRule(rule, name, facts, path, fallback)
	-- "com_apple_MobileAsset_UAF_FM_GenerativeModels" is the asset type
	-- com.apple.MobileAsset.UAF.FM.GenerativeModels.
	local asset = name:match("^com_apple_MobileAsset_(.+)$")
	if asset then return {owner = "macOS", kind = rule.kind, what = fill(rule.what, (asset:gsub("_", " ")))} end
	local owner = ownerOf(name, rule, facts, path) or fallback
	if owner then return {owner = owner, kind = rule.kind, what = fill(rule.what, owner)} end
	if rule.system then return {owner = "macOS", kind = rule.kind, what = rule.unknown} end
	-- Only an identifier no installed app claims is evidence of a removed
	-- app; "vscode-cpptools" may belong to a tool, a helper or a plug-in.
	local identified = Leftovers.identifier((name:gsub("%.plist$", ""))) or name:match("^%x+%-%x+%-%x+%-%x+%-%x+$")
	if not facts.apps or not identified then return {kind = rule.kind} end
	return {kind = rule.kind, what = rule.unknown, unclaimed = true}
end

function Explain.path(path, facts)
	if type(path) ~= "string" then return nil end
	facts = facts or {}
	local short = tilde(path, facts.home)
	local location = Map.find(short) or Map.find(path)
	if location then return {owner = location.owner, kind = location.name, what = location.what} end
	local name = short:match("([^/]+)$")
	if not name then return nil end
	local named = Library.names[name:lower()]
	if named then return {owner = named.owner, kind = named.kind, what = named.what} end
	local parent = short:match("^(.*)/[^/]+$")
	local container, inside = short:match("^~/Library/Containers/([^/]+)/(.+)$")
	if container then
		local rule = {byId = true}
		local owner = ownerOf(container, rule, facts, (path:match("^(.*/Library/Containers/[^/]+)")))
		-- A sandbox holds its own Library: its Caches are a cache, and so on.
		local sub = inside:match("^Data/Library/([^/]+)/[^/]+$")
		local inner = sub and Library.parents["~/Library/" .. sub]
		if inner then return byRule(inner, name, facts, path, owner) end
		if owner then return {owner = owner, kind = "Sandbox", what = "Part of " .. owner .. "'s sandbox. Manage its data from inside the app."} end
	end
	local rule = parent and Library.parents[parent]
	if rule then return byRule(rule, name, facts, path) end
	return nil
end

-- The sentence for the packages an installer receipt names
-- (`pkgutil --file-info` lists each as "pkgid: com.example.pkg"), or nil.
function Explain.packages(output)
	local ids = {}
	for id in (output or ""):gmatch("pkgid: ([^\n]+)") do table.insert(ids, id) end
	return ids
end
function Explain.package(ids)
	if not ids or #ids == 0 then return nil end
	if #ids == 1 then return "Installed by the package " .. ids[1] .. "." end
	return "Installed by the package " .. ids[1] .. " and " .. (#ids - 1) .. " more."
end

return Explain
