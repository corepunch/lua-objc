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

-- Installed apps as {bundleId, name}. Returns lookup sets for identifiers,
-- vendors and display names.
function Leftovers.index(apps)
	local ids, vendors, names = {}, {}, {}
	for _, app in ipairs(apps or {}) do
		if type(app.bundleId) == "string" then
			ids[app.bundleId:lower()] = true
			for name in pairs(Leftovers.supportNames(app.bundleId) or {}) do names[name] = true end
			local v = vendor(app.bundleId)
			if v then
				vendors[v] = true
				-- "Google" in Application Support belongs to com.google.Chrome.
				names[v:match("%.(.+)$")] = true
			end
		end
		if type(app.name) == "string" then
			local name = app.name:lower():gsub("%.app$", "")
			names[name] = true
			-- "Code" belongs to "Visual Studio Code"; match a trailing word too.
			local last = name:match("(%w+)$")
			if last then names[last] = true end
		end
	end
	return {ids = ids, vendors = vendors, names = names}
end

-- The bundle identifier a Library folder name refers to, if it names one.
-- Handles "com.x.app", "com.x.app.savedState", "group.com.x.app" and team
-- prefixed group containers such as "ABCDE12345.com.x.shared".
function Leftovers.identifier(name)
	local id = name:gsub("%.savedState$", ""):gsub("%.binarycookies$", "")
	id = id:gsub("^group%.", ""):gsub("^%u%w%w%w%w%w%w%w%w%w%.", "")
	if id:match("^[%w%-]+%.[%w%-]+%.[%w%-%.]+$") then return id end
end

-- Classifies one folder. Returns a tier id or nil when the folder belongs to
-- an installed app or to macOS. `byName` allows folders named after an app
-- rather than an identifier, as in Application Support.
function Leftovers.classify(name, byName, installed)
	if Leftovers.system[name] or name:sub(1, 1) == "." then return nil end
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
		return "high"
	end
	if byName then
		if installed.names[name:lower()] then return nil end
		return "low"
	end
	return nil
end

return Leftovers
