local Leftovers = {}

-- Folders macOS and its services own. They are never leftovers, whatever
-- their name looks like.
Leftovers.system = {
	["AddressBook"] = true, ["CallHistoryDB"] = true, ["CallHistoryTransactions"] = true, ["CloudDocs"] = true,
	["CrashReporter"] = true, ["DiskImages"] = true, ["Dock"] = true, ["FileProvider"] = true,
	["Knowledge"] = true, ["MobileSync"] = true, ["iCloud"] = true, ["icdd"] = true, ["Animoji"] = true,
	["AppStore"] = true, ["accountsd"] = true, ["ControlCenter"] = true, ["DifferentialPrivacy"] = true,
	["Family"] = true, ["FaceTime"] = true, ["networkserviceproxy"] = true, ["NotificationCenter"] = true,
	["Quick Look"] = true, ["SyncServices"] = true, ["TrustedPeersHelper"] = true, ["videosubscriptionsd"] = true,
	["homeenergyd"] = true, ["identityservicesd"] = true, ["tipsd"] = true, ["Wallpaper"] = true,
	["CloudKit"] = true, ["GeoServices"] = true, ["com.crashlytics"] = true, ["SiriTTS"] = true,
}

Leftovers.tiers = {
	high = {rank = 1, label = "App not installed", confidence = "High"},
	medium = {rank = 2, label = "Vendor has other apps", confidence = "Medium"},
	low = {rank = 3, label = "Name only", confidence = "Low"},
}

local function vendor(identifier)
	local a, b = identifier:match("^([%w%-]+)%.([%w%-]+)%.")
	return a and (a .. "." .. b):lower() or nil
end

-- Some apps use a product storage name independently of their bundle's
-- Finder name. Claim only an explicit folder for its exact installed bundle
-- identity; sharing a vendor or a filename is not proof of ownership.
local SUPPORT_NAMES = {['com.openai.codex'] = {codex = true}}
function Leftovers.supportNames(bundleId)
	return type(bundleId) == 'string' and SUPPORT_NAMES[bundleId:lower()] or nil
end

-- `mdls -raw -name kMDItemCFBundleIdentifier -name kMDItemDisplayName a b …`
-- prints both values for each bundle in turn, separated by NUL, "(null)"
-- for a missing one. Bundles without an identifier are left out.
function Leftovers.parseApplications(output, paths)
	local values = {}
	for value in ((output or "") .. "\0"):gmatch("([^%z]*)%z") do table.insert(values, value) end
	local apps = {}
	for index, path in ipairs(paths) do
		local id, name = values[index * 2 - 1], values[index * 2]
		if id and id ~= "" and id ~= "(null)" then
			name = (name and name ~= "(null)" and name ~= "") and name:gsub("%.app$", "") or path:match("([^/]+)%.app$")
			table.insert(apps, {path = path, bundleId = id, name = name})
		end
	end
	return apps
end

local function append(map, key, name)
	map[key] = map[key] or {}
	for _, existing in ipairs(map[key]) do if existing == name then return end end
	table.insert(map[key], name)
end

-- Installed apps as {bundleId, name, team, groups}. Returns lookup sets for
-- identifiers, vendors and display names, and who each identifier, app
-- group and team belongs to: `owners[id]`, `groups[group]` and
-- `teams[team]` list app names.
function Leftovers.index(apps)
	local ids, vendors, names, owners, groups, teams = {}, {}, {}, {}, {}, {}
	for _, app in ipairs(apps or {}) do
		local title = type(app.name) == "string" and app.name:gsub("%.app$", "") or nil
		if type(app.bundleId) == "string" then
			local id = app.bundleId:lower()
			ids[id] = true
			if title then append(owners, id, title) end
			for name in pairs(Leftovers.supportNames(app.bundleId) or {}) do names[name] = true end
			local v = vendor(app.bundleId)
			if v then
				vendors[v] = true
				-- "Google" in Application Support belongs to com.google.Chrome.
				names[v:match("%.(.+)$")] = true
			end
		end
		if title then
			local name = title:lower()
			names[name] = true
			-- "Code" belongs to "Visual Studio Code"; match a trailing word too.
			local last = name:match("(%w+)$")
			if last then names[last] = true end
			for _, group in ipairs(app.groups or {}) do append(groups, group:lower(), title) end
			if type(app.team) == "string" then append(teams, app.team, title) end
		end
	end
	return {ids = ids, vendors = vendors, names = names, owners = owners, groups = groups, teams = teams}
end

-- The bundle identifier a Library folder name refers to, if it names one.
-- Handles "com.x.app", "com.x.app.savedState", "group.com.x.app" and team
-- prefixed group containers such as "ABCDE12345.com.x.shared". A team ID
-- is ten capital letters and digits and may start with a digit, as Apple's
-- own "243LU875E5.groups.com.apple.podcasts" does.
local TEAM = "^" .. ("[%u%d]"):rep(10) .. "%."
local TEAM_ID = "^(" .. ("[%u%d]"):rep(10) .. ")%."
function Leftovers.identifier(name)
	local id = name:gsub("%.savedState$", ""):gsub("%.binarycookies$", "")
	id = id:gsub("^group%.", ""):gsub(TEAM, ""):gsub("^groups%.", "")
	if id:match("^[%w%-]+%.[%w%-]+%.[%w%-%.]+$") then return id end
end

-- Classifies one folder. Returns a tier id or nil when the folder belongs to
-- an installed app or to macOS. `byName` allows folders named after an app
-- rather than an identifier, as in Application Support.
function Leftovers.classify(name, byName, installed)
	if Leftovers.system[name] or name:sub(1, 1) == "." then return nil end
	-- An installed app that declares the folder as its app group claims it.
	if installed.groups and installed.groups[name:lower()] then return nil end
	local id = Leftovers.identifier(name)
	if id then
		local lower = id:lower()
		if lower:match("^com%.apple%.") or lower:match("^apple%.") then return nil end
		for installedId in pairs(installed.ids) do
			-- Helpers, extensions and shared containers share their app's
			-- prefix, in either direction: an installed app claims its
			-- helpers' folders, and an installed helper its host's.
			if lower == installedId or lower:sub(1, #installedId + 1) == installedId .. "."
				or installedId:sub(1, #lower + 1) == lower .. "." then return nil end
		end
		local v = vendor(id)
		if v and installed.vendors[v] then return "medium" end
		-- A developer whose other apps are installed: not proof of either.
		local team = name:match(TEAM_ID)
		if team and installed.teams and installed.teams[team] then return "medium" end
		return "high"
	end
	if byName then
		if installed.names[name:lower()] then return nil end
		return "low"
	end
	return nil
end

-- The installed apps a Library folder or file belongs to, as a list of
-- names, or nil: an app group an app declares, the bundle identifier
-- (helpers and extensions share their app's prefix), then the apps of the
-- developer whose team ID prefixes the name. `byName` also accepts a folder
-- named after an app, as in Application Support. `how` says which matched:
-- "group", "identifier", "team" or "name".
function Leftovers.owner(name, installed, byName)
	if not installed or type(name) ~= "string" then return nil end
	local lower = name:lower():gsub("%.plist$", "")
	if installed.groups and installed.groups[lower] then return installed.groups[lower], "group" end
	local id = Leftovers.identifier((name:gsub("%.plist$", "")))
	if id and installed.owners then
		id = id:lower()
		local best
		for installedId, names in pairs(installed.owners) do
			if id == installedId or id:sub(1, #installedId + 1) == installedId .. "." then
				if not best or #installedId > #best then best = installedId end
			end
		end
		if best then return installed.owners[best], "identifier" end
	end
	local team = name:match(TEAM_ID)
	if team and installed.teams and installed.teams[team] then return installed.teams[team], "team" end
	if byName and installed.names and installed.names[lower] then return {name}, "name" end
	return nil
end

return Leftovers
