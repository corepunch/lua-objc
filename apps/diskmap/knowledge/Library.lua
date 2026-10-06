-- What a folder inside a Library is, when knowledge/Filesystem has no entry
-- for its exact path. Most of a Library is folders apps create one per app,
-- named by the app's bundle identifier ("com.example.App"), an app group
-- ("group.com.example.shared"), or a developer's team ID and a group name
-- ("UBF8T346G9.Office"). The parent says what kind of data it is; the name
-- says whose (helpers/Explain.lua resolves it against the installed apps).
-- Plain data, read three ways:
--
-- · `parents`: the meaning of a child of a known folder. `what` and
--   `unknown` are sentences with "%s" for the owner's name; `unknown` is
--   used when no installed app claims a folder named by an identifier; a
--   plain name nobody claims proves nothing and says nothing. `byId` and `byName` say
--   how children are named; a `system` folder's children are macOS's, so
--   none is ever called unclaimed;
-- · `services`: Apple's background services and the feature a person knows
--   them by, so "com.apple.bird" reads as iCloud Drive. Apple's own apps
--   need no entry: their bundles are installed, so they resolve like any app;
-- · `names`: folder names that mean the same wherever they appear.
--
-- Statements were checked against Apple's File System Programming Guide,
-- Eclectic Light Company articles and Apple Support Communities threads
-- (October 2026); see docs/research/DISKMAP_LIBRARY_QUESTIONS.md.
local Library = {}

local function cache(where)
	return {kind = "Cache", byId = true, byName = true,
		what = "%s's cache: data it downloads or rebuilds by itself. Clear it from %s's settings, or quit %s before moving the folder to the Trash.",
		unknown = "A cache no installed app claims; it may belong to an app you removed. Caches are rebuilt, so it can go once nothing uses it." .. (where or "")}
end

Library.parents = {
	["~/Library/Caches"] = cache(),
	["/Library/Caches"] = cache(" An administrator's password is needed to remove it."),
	["~/Library/Application Support"] = {kind = "App data", byId = true, byName = true,
		what = "Data %s keeps: libraries, databases, downloads and state it cannot always rebuild. Manage it from %s; removing it may lose your work in it.",
		unknown = "Data no installed app claims; it may be left from an app you removed. Look inside before removing it: it may hold documents or downloads."},
	["/Library/Application Support"] = {kind = "Shared app data", byId = true, byName = true,
		what = "Data %s installed for every account: plug-ins, licenses, sound libraries or helpers. Remove it with %s's own uninstaller.",
		unknown = "Data an installer put here for every account; no installed app claims it by name. Check the developer's uninstall instructions before removing it."},
	["~/Library/Containers"] = {kind = "Sandbox", byId = true,
		what = "%s's sandbox: its private settings, caches and documents. Removing it resets %s completely; manage its data from inside the app.",
		unknown = "The sandbox of an app that is no longer installed, or of an extension. macOS never removes containers by itself. Check Data/Documents inside before removing it."},
	["~/Library/Group Containers"] = {kind = "Shared container", byId = true,
		what = "Data %s shares between its apps, widgets and extensions. Several apps from one developer may rely on it; manage it from the apps.",
		unknown = "Data shared by apps of one developer, none of which declares it now. The prefix is the developer's team ID. Remove it only when you no longer use that developer's apps."},
	["~/Library/Daemon Containers"] = {kind = "Service sandbox", system = true,
		what = "The private storage of a macOS background service (%s). macOS manages it.",
		unknown = "The private storage of a macOS background service. macOS manages it."},
	["~/Library/Preferences"] = {kind = "Settings", byId = true,
		what = "%s's settings. Deleting it resets %s to its defaults; quit %s first, since apps rewrite their settings as they quit.",
		unknown = "Settings of an app that is no longer installed. A few kilobytes; it does no harm."},
	["/Library/Preferences"] = {kind = "Shared settings", byId = true,
		what = "Settings %s keeps for every account.",
		unknown = "Settings kept for every account by software that is no longer installed."},
	["~/Library/Saved Application State"] = {kind = "Saved windows", byId = true,
		what = "The windows %s reopens when it launches. Safe to remove: %s simply opens fresh.",
		unknown = "Saved windows of an app that is no longer installed. Safe to remove."},
	["~/Library/HTTPStorages"] = {kind = "Network storage", byId = true,
		what = "Cookies and cached responses from %s's network requests. Removing it may sign %s out of web services.",
		unknown = "Cookies and cached responses of an app that is no longer installed. Safe to remove."},
	["~/Library/WebKit"] = {kind = "Web data", byId = true,
		what = "Website data of the web pages %s shows in its windows. Removing it may sign %s out of web services.",
		unknown = "Website data of an app that is no longer installed. Safe to remove."},
	["~/Library/Logs"] = {kind = "Logs", byId = true, byName = true,
		what = "%s's logs. They help diagnose problems; old logs can go to the Trash.",
		unknown = "Logs. They help diagnose problems; old logs can go to the Trash."},
	["~/Library/LaunchAgents"] = {kind = "Login agent", byId = true,
		what = "A background program launchd starts for %s when you log in. Turn it off in System Settings › General › Login Items & Extensions.",
		unknown = "A background program launchd starts when you log in, from an app that is no longer installed. Check the program it names, then remove it and log out and back in."},
	["/Library/LaunchAgents"] = {kind = "Login agent", byId = true,
		what = "A background program launchd starts for %s when anyone logs in. Turn it off in System Settings › General › Login Items & Extensions.",
		unknown = "A background program launchd starts at every login, from software that is no longer installed. Removing it needs an administrator; use the developer's uninstaller if there is one."},
	["/Library/LaunchDaemons"] = {kind = "Startup daemon", byId = true,
		what = "A background program launchd starts for %s at startup, before anyone logs in. Remove it with %s's uninstaller.",
		unknown = "A background program launchd starts at startup, from software that is no longer installed. Removing it needs an administrator; use the developer's uninstaller if there is one."},
	["/Library/PrivilegedHelperTools"] = {kind = "Privileged helper", byId = true,
		what = "A helper %s runs as an administrator. Remove it with %s's uninstaller.",
		unknown = "A helper an app installed to run as an administrator; the app is no longer installed. Use the developer's uninstaller, or remove it together with its startup daemon."},
	["/System/Library/AssetsV2"] = {kind = "System asset", system = true,
		what = "Components macOS downloaded for %s. macOS manages them and System Integrity Protection keeps them from being deleted by hand.",
		unknown = "Components macOS downloaded for one of its features. macOS manages them and System Integrity Protection keeps them from being deleted by hand."},
}

-- Apple's background services by the name in their folders (after
-- "com.apple." or "group.com.apple."), or a folder name that is a service.
Library.services = {
	["bird"] = "iCloud Drive", ["clouddocs"] = "iCloud Drive", ["cloudd"] = "iCloud", ["cloudkit"] = "iCloud",
	["icloud"] = "iCloud", ["icloudwebd"] = "iCloud", ["mediaanalysisd"] = "Photos analysis",
	["photoanalysisd"] = "Photos analysis", ["photolibraryd"] = "Photos", ["corespotlightd"] = "Spotlight",
	["spotlight"] = "Spotlight", ["spotlightui"] = "Spotlight", ["biome"] = "Siri and Screen Time", ["biomed"] = "Siri and Screen Time",
	["idleassetsd"] = "Aerial wallpapers", ["mobileassetd"] = "Downloaded system assets",
	["softwareupdate"] = "Software Update", ["softwareupdated"] = "Software Update", ["nsurlsessiond"] = "Background downloads",
	["appstoreagent"] = "App Store", ["appstore"] = "App Store", ["commerce"] = "App Store",
	["ampartworkagent"] = "Music artwork", ["amplibraryagent"] = "Music library", ["amsengagementd"] = "Apple Media Services",
	["appleaccountd"] = "Apple Account", ["akd"] = "Apple Account", ["familycircled"] = "Family Sharing",
	["identityservicesd"] = "iMessage and FaceTime", ["imagent"] = "Messages", ["suggestd"] = "Siri suggestions",
	["siri"] = "Siri", ["assistantd"] = "Siri", ["knowledge-agent"] = "Siri and Screen Time", ["homed"] = "Home",
	["helpd"] = "Help Viewer", ["quicklook"] = "Quick Look", ["sharedfilelist"] = "Recent items and Finder sidebar",
	["containermanagerd"] = "App sandboxes", ["deleted"] = "Storage purging", ["tipsd"] = "Tips",
	["translationd"] = "Translation", ["intelligenceplatform"] = "Apple Intelligence", ["geod"] = "Maps", ["findmy"] = "Find My",
	["geoservices"] = "Maps", ["parsecd"] = "Spotlight suggestions", ["visualintelligence"] = "Visual Look Up",
	["iwork"] = "Pages, Numbers and Keynote", ["stickersd"] = "Stickers", ["systempreferences"] = "System Settings",
}

-- Folder names (lowercased) that mean the same wherever they appear.
Library.names = {
	["precache"] = {kind = "Not Apple's", what = "Not part of macOS: no Apple folder is called precache. An app or script made it to download something ahead of time, often updates for Content Caching. What macOS itself downloads ahead of time, staged updates, lives in /System/Library/AssetsV2 and is removed by macOS."},
	[".spotlight-v100"] = {kind = "Spotlight index", owner = "Spotlight", what = "Spotlight's search index for this disk. Rebuild it from Spotlight's Privacy settings rather than deleting it."},
	[".fseventsd"] = {kind = "File change log", owner = "macOS", what = "The record of file changes Time Machine and Spotlight read. macOS trims it."},
	[".documentrevisions-v100"] = {kind = "Document versions", owner = "macOS", what = "Earlier versions of documents apps save with Versions. Browse them with File › Revert To in the app."},
	[".temporaryitems"] = {kind = "Temporary items", owner = "macOS", what = "Files apps save to this disk temporarily. macOS clears it."},
	[".trashes"] = {kind = "Trash", owner = "Finder", what = "This disk's Trash. Empty the Trash in Finder to free it."},
	["__macosx"] = {kind = "Archive leftovers", what = "Finder metadata left by extracting a zip made on a Mac. Safe to remove."},
	[".ds_store"] = {kind = "Finder view settings", owner = "Finder", what = "How Finder shows this folder: icon positions and view options. Tiny; Finder recreates it."},
	["node_modules"] = {kind = "Packages", what = "JavaScript packages a project installed. npm install or a similar command restores them from the project's lockfile."},
	["__pycache__"] = {kind = "Compiled Python", what = "Bytecode Python compiles from source files. Safe to remove; Python recreates it."},
}

return Library
