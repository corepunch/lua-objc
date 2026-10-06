-- A map of the macOS file system: every location worth knowing on a Mac
-- running macOS 26 or later, what it holds, who may read it and where
-- leftovers collect. It is plain data, read three ways:
--
-- · the macOS Folders page presents it area by area, with live sizes, so a
--   person can learn what goes where and how much it takes;
-- · the scan skips `guard = "sip"` and `guard = "owner"` locations, which no
--   app can read, and the Overview names them instead of blaming Full Disk
--   Access for them;
-- · locations marked `leftover` become catalog resources (catalog/Leftovers)
--   so an interrupted update or install shows up in Clean Up.
--
-- Location fields:
--   path      exact path; "~" is the home folder
--   name      short name, as the page lists it
--   what      what it holds and how macOS uses it
--   guard     who may read it (see Filesystem.guards); nil when apps can
--   volume    APFS role whose own used space is the location's size
--   expected  present on every Mac of this macOS version
--   resource  catalog id that measures it
--   feature   what several locations serve together, named once
--   owner     the app or macOS service that writes it, as a person knows it
--   leftover  {id, remover, threshold, advice}: where interrupted or stale
--             data stays, and who clears it (restart, update, finder)
--
-- Guards, sizes and presence were verified with `ls -ldO`, `stat -f %Xf`
-- and `diskutil apfs list` on macOS 27. A location missing from a Mac is
-- simply absent there; Diskmap never creates or removes anything here.
local Filesystem = {}

Filesystem.guards = {
	sip = {title = "Protected by System Integrity Protection",
		detail = "The folder carries macOS's restricted flag. No app can list it, whatever permission it holds, and neither can an administrator."},
	owner = {title = "Readable only by macOS",
		detail = "A macOS system account owns the folder and alone may list it. Full Disk Access does not change that."},
	privacy = {title = "Needs Full Disk Access",
		detail = "macOS privacy protection. Diskmap can measure it once Full Disk Access is on."},
}

local assets = "/System/Library/AssetsV2/com_apple_MobileAsset_"
local intelligence = "Apple Intelligence models"

Filesystem.areas = {
	{id = "volumes", title = "Volumes on your startup disk", icon = "internaldrive",
		summary = "One APFS container, several volumes sharing its free space. Each volume's size is the one Disk Utility shows.",
		locations = {
			{path = "/", name = "Macintosh HD", volume = "System", expected = true,
				what = "The Signed System Volume: a sealed, read-only snapshot of macOS. Its size changes only with a macOS update."},
			{path = "/System/Volumes/Data", name = "Macintosh HD – Data", volume = "Data", expected = true,
				what = "Everything that is yours and everything macOS writes at runtime. Firmlinks show its folders at the top of the disk."},
			{path = "/System/Volumes/Preboot", name = "Preboot", volume = "Preboot", expected = true, resource = "preboot",
				what = "Boot files, the FileVault unlock screen and the cryptexes that carry Safari and the shared code cache. It grows while an update is staged and shrinks once it installs. Its files are clones, so adding them up counts shared blocks several times; the volume's own size is the true one."},
			{path = "/System/Volumes/Recovery", name = "Recovery", volume = "Recovery", expected = true, resource = "recovery",
				what = "The recoveryOS used to reinstall macOS, restore from Time Machine or repair the disk. Usually not mounted; its size comes from APFS."},
			{path = "/System/Volumes/VM", name = "Swap", volume = "VM", expected = true, resource = "vm",
				what = "Swap files macOS pages memory out to under memory pressure, and the sleep image on Intel Macs. Restarting releases swap."},
			{path = "/System/Volumes/Update", name = "Update", volume = "Update", expected = true, resource = "update-volume",
				what = "Where Software Update prepares a macOS update. A few hundred megabytes between updates; gigabytes while one is prepared or stuck."},
		}},
	{id = "top", title = "The top of the disk", icon = "folder",
		summary = "What Finder shows at the top of Macintosh HD, and the hidden Unix folders beside it.",
		locations = {
			{path = "/Applications", name = "Applications", expected = true, resource = "apps-system-other",
				what = "Apps installed for everyone. Apple's own apps live on the sealed system volume at /System/Applications and only appear here."},
			{path = "/System/Applications", name = "Apple apps", expected = true, resource = "apps-builtin",
				what = "Safari, Mail, Music and the other apps that ship with macOS. They are part of the sealed system and cannot be removed."},
			{path = "/Users", name = "Users", expected = true, resource = "users-other",
				what = "A home folder for every account, and Shared for files every account can reach."},
			{path = "/Users/Shared", name = "Shared", expected = true,
				what = "Files meant for every account. Installers of music and creative apps sometimes leave large sample libraries here."},
			{path = "/Library", name = "Library", expected = true, resource = "library-shared",
				what = "Resources shared by every account: fonts, drivers, caches, app support installed by administrators."},
			{path = "/System", name = "System", expected = true, resource = "system",
				what = "macOS itself, on the sealed read-only volume, plus firmlinked folders such as AssetsV2 that live on the Data volume."},
			{path = "/usr", name = "usr", expected = true, resource = "unix",
				what = "Unix commands and libraries. /usr/local is the one part that belongs to you: tools installed outside the App Store."},
			{path = "/usr/local", name = "usr/local", resource = "usr-local",
				what = "Command-line tools you or an installer added, including Homebrew on Intel Macs."},
			{path = "/opt/homebrew", name = "Homebrew", resource = "brew-install",
				what = "Homebrew's packages on Apple silicon."},
			{path = "/private", name = "private", expected = true, resource = "private-other",
				what = "Where /etc, /tmp and /var really live. macOS keeps its working data, logs and databases here."},
			{path = "/cores", name = "Core dumps", expected = true,
				what = "Memory images written when a process crashes with core dumps enabled. Normally empty; a single dump can take gigabytes.",
				leftover = {id = "core-dumps", remover = "finder", threshold = 100e6, advice = "Core dumps are only useful to the developer debugging the crash. Move them to the Trash once no one needs them."}},
			{path = "/macOS Install Data", name = "macOS Install Data",
				what = "Staging for a macOS installation started from an Install macOS app. It is removed when the installation finishes; one left behind is an interrupted install.",
				leftover = {id = "install-data", remover = "update", threshold = 500e6, advice = "Finish or cancel the macOS installation. If no installation is pending, restart; macOS removes an abandoned staging folder, and the Install macOS app can be downloaded again."}},
		}},
	{id = "data-hidden", title = "Hidden at the top of the Data volume", icon = "eye.slash",
		summary = "Volume-wide databases macOS keeps out of sight. Most are readable only by macOS itself.",
		locations = {
			{path = "/System/Volumes/Data/.Spotlight-V100", name = "Spotlight index", guard = "owner", expected = true,
				what = "The search index for the Data volume. It grows with the number of files and mail messages. Rebuild it by adding the disk to Spotlight's privacy list and removing it again."},
			{path = "/System/Volumes/Data/.fseventsd", name = "File change log", guard = "owner", expected = true,
				what = "The record of file changes that Time Machine, Spotlight and sync apps read. macOS trims it on its own."},
			{path = "/System/Volumes/Data/.DocumentRevisions-V100", name = "Document versions", guard = "owner", expected = true,
				what = "Earlier versions of documents that apps save with Versions. Large edited files keep large histories. Manage them from File › Revert To in the app."},
			{path = "/System/Volumes/Data/.PreviousSystemInformation", name = "Previous system information", expected = true,
				what = "Details of the macOS version before the last update, kept for Migration and diagnostics."},
			{path = "/System/Volumes/Data/MobileSoftwareUpdate", name = "Update staging (Data)",
				what = "Where macOS unpacks parts of an update on the Data volume. Normally a few megabytes; gigabytes mean an update is prepared or was interrupted.",
				leftover = {id = "data-update-staging", remover = "update", threshold = 1e9, advice = "Open System Settings › General › Software Update and install or retry the pending update. macOS removes the staging when the update completes; do not delete it by hand."}},
		}},
	{id = "system", title = "Inside /System", icon = "gearshape.2",
		summary = "The operating system. Only the asset store changes between updates.",
		locations = {
			{path = "/System/Library/AssetsV2", name = "Downloaded system assets", expected = true, resource = "mobile-assets",
				what = "The MobileAsset store: models, voices, fonts, dictionaries, wallpapers and software updates macOS downloads when a feature needs them. It lives on the Data volume through a firmlink."},
			{path = assets .. "UAF_FM_GenerativeModels", name = "Apple Intelligence language model", guard = "sip", feature = intelligence,
				what = "The on-device foundation model behind Writing Tools, summaries and Siri. Several gigabytes when Apple Intelligence is on."},
			{path = assets .. "UAF_FM_Visual", name = "Apple Intelligence visual model", guard = "sip", feature = intelligence,
				what = "The on-device model that understands images, used by Image Playground and visual look-up."},
			{path = assets .. "UAF_FM_CodeLM", name = "Apple Intelligence coding model", guard = "sip", feature = intelligence,
				what = "The on-device model behind predictive code completion in Xcode."},
			{path = assets .. "UAF_FM_Overrides", name = "Apple Intelligence model updates", guard = "sip", feature = intelligence,
				what = "Adapters and updates applied on top of the foundation models."},
			{path = assets .. "UAF_IF_Planner", name = "Apple Intelligence planner", guard = "sip", feature = intelligence,
				what = "The model that plans multi-step requests for Siri and App Intents."},
			{path = assets .. "UAF_IF_PlannerOverrides", name = "Apple Intelligence planner updates", guard = "sip", feature = intelligence,
				what = "Updates applied on top of the planner model."},
			{path = assets .. "MacSoftwareUpdate", name = "Downloaded macOS updates", resource = "update-assets-2",
				what = "Update payloads Software Update downloaded. A paused, deferred or failed download stays here until macOS installs, retries or purges it."},
			{path = "/System/Library/AssetsV2/PreinstalledAssetsV2", name = "Preinstalled assets", expected = true,
				what = "Assets that shipped with macOS and are replaced as newer versions download."},
			{path = "/System/Cryptexes", name = "Cryptexes", expected = true,
				what = "Mount points for the cryptexes stored in Preboot: Safari, the shared code cache and Rapid Security Responses. Their space counts in Preboot."},
			{path = "/System/Library/Speech", name = "Speech", expected = true, resource = "speech",
				what = "Speech engines and voices that ship with macOS."},
		}},
	{id = "library", title = "Inside /Library", icon = "books.vertical",
		summary = "Shared by every account on this Mac. Installers and administrators write here.",
		locations = {
			{path = "/Library/Caches", name = "Shared caches", expected = true, resource = "system-caches",
				what = "Caches of system services and apps installed for everyone. macOS rebuilds them."},
			{path = "/Library/Logs", name = "Shared logs", expected = true, resource = "shared-logs",
				what = "Diagnostic reports, install logs and logs of system-wide apps."},
			{path = "/Library/Application Support", name = "Shared application support", expected = true,
				what = "Data of apps installed for every account, license files, plug-in content and sound libraries."},
			{path = "/Library/Application Support/com.apple.idleassetsd/Customer", name = "Aerial wallpapers", resource = "aerials",
				what = "Aerial screen savers and wallpapers you downloaded in Wallpaper settings. Each is hundreds of megabytes; remove them from Wallpaper settings."},
			{path = "/Library/Developer", name = "Shared developer tools",
				what = "Command Line Tools and simulator runtimes shared by every account."},
			{path = "/Library/Updates", name = "Legacy updates", expected = true,
				what = "Where macOS put updates before Big Sur. Today it holds only a small index; anything large here is a leftover from an old update.",
				leftover = {id = "legacy-updates", remover = "finder", threshold = 500e6, advice = "Current macOS no longer installs from here. Review the contents in Finder; files left from an old update can be moved to the Trash."}},
			{path = "/Library/Trial", name = "Trial experiments", expected = true, guard = "privacy",
				what = "Settings and small models macOS downloads for features being tuned by Apple."},
			{path = "/Library/Audio", name = "Audio", expected = true,
				what = "Audio drivers, plug-ins and sound libraries. GarageBand and Logic add gigabytes of instruments to Apple Loops here."},
			{path = "/Library/Fonts", name = "Shared fonts", expected = true,
				what = "Fonts installed for every account."},
			{path = "/Library/Receipts", name = "Installer receipts", expected = true,
				what = "Records of packages installed with the Installer. Small."},
			{path = "/Library/LaunchAgents", name = "Login agents for everyone", expected = true,
				what = "Background programs launchd starts for every account at login, added by installers. Each property list names the program it runs. Turn one off in System Settings › General › Login Items & Extensions; remove it with the app that installed it."},
			{path = "/Library/LaunchDaemons", name = "Startup daemons", expected = true,
				what = "Background programs launchd starts at startup, before anyone logs in, added by installers such as VPN, backup and driver software. Remove one with the app that installed it."},
			{path = "/Library/PrivilegedHelperTools", name = "Privileged helpers", expected = true,
				what = "Programs apps installed to run as an administrator, such as Docker's network helper. A helper stays after its app is dragged to the Trash; the app's own uninstaller removes it."},
			{path = "/Library/Application Support/Apple/AssetCache/Data", name = "Content Caching", owner = "Content Caching",
				what = "Software updates, apps and iCloud data this Mac caches for other Apple devices on the network when Content Caching is on in System Settings › General › Sharing. Tools that fill it ahead of time are often called “precache”. Clear it with Reset in Content Caching's options (the ⓘ button beside it in Sharing), or turn Content Caching off."},
		}},
	{id = "var", title = "Inside /private/var", icon = "cylinder.split.1x2",
		summary = "macOS's own working data: temporary files, logs and service databases.",
		locations = {
			{path = "/private/var/folders", name = "Per-user temporary files", expected = true, resource = "temporary",
				what = "Each account's $TMPDIR and system caches such as Quick Look thumbnails and App Store downloads. Restarting clears stale temporary files."},
			{path = "/private/tmp", name = "tmp", expected = true,
				what = "Temporary files of command-line tools and installers; /tmp is a link to it. macOS empties it at every restart.",
				leftover = {id = "tmp", remover = "restart", threshold = 1e9, advice = "Restart your Mac: macOS empties /tmp at startup. Files no running app uses can also go to the Trash in Finder now; an app still writing here would lose its working files."}},
			{path = "/private/var/tmp", name = "var/tmp", expected = true,
				what = "Temporary files meant to survive a restart. macOS removes old ones periodically.",
				leftover = {id = "var-tmp", remover = "finder", threshold = 1e9, advice = "Review the files in Finder. Files older than a few days that no app is using can be moved to the Trash."}},
			{path = "/private/var/log", name = "System logs", expected = true, resource = "private-logs",
				what = "Text logs of Unix services and installs. macOS rotates them."},
			{path = "/private/var/db/diagnostics", name = "Unified log", expected = true, resource = "unified-log",
				what = "The system log Console reads. macOS keeps it to a size budget and removes old entries."},
			{path = "/private/var/db/uuidtext", name = "Unified log strings", expected = true, resource = "unified-log-strings",
				what = "Format strings the unified log refers to. It grows and shrinks with the log."},
			{path = "/private/var/db/powerlog", name = "Power log", expected = true, resource = "power-log",
				what = "Battery and energy history behind Battery settings. macOS trims it."},
			{path = "/private/var/db/receipts", name = "Package receipts", expected = true,
				what = "Bills of materials for packages installed with the Installer, used to update or verify them."},
			{path = "/private/var/db/softwareupdate", name = "Software Update data", expected = true,
				what = "Software Update's own records and catalogs."},
			{path = "/private/var/db/com.apple.xpc.roleaccountd.staging", name = "App install staging", guard = "sip", expected = true,
				what = "Where the App Store and installers stage an app before moving it into place. A download interrupted mid-install can leave data here until macOS cleans it up; restarting and reopening the App Store lets it finish or discard it."},
			{path = "/private/var/install", name = "macOS install staging", guard = "sip",
				what = "Staging for a macOS installation in progress. macOS removes it when the installation completes or is abandoned."},
			{path = "/private/var/MobileSoftwareUpdate", name = "Update brain", expected = true,
				what = "The Software Update engine macOS downloads for each update.",
				leftover = {id = "update-brain", remover = "update", threshold = 1e9, advice = "Install or retry the pending update in System Settings › General › Software Update. macOS replaces this with every update."}},
			{path = "/private/var/db/oah", name = "Rosetta translations", guard = "sip",
				what = "Intel apps translated for Apple silicon by Rosetta. Grows with every Intel app you run; macOS rebuilds it."},
			{path = "/private/var/db/KernelExtensionManagement/Staging", name = "Staged system extensions", guard = "sip",
				what = "Kernel and system extensions waiting for approval or a restart."},
			{path = "/private/var/db/Spotlight-V100", name = "System Spotlight index", guard = "owner", expected = true,
				what = "Spotlight's index for system locations."},
			{path = "/private/var/db/fseventsd", name = "System file change log", guard = "owner", expected = true,
				what = "File change records for the system volume."},
			{path = "/private/var/db/biome", name = "Activity streams", guard = "owner", expected = true,
				what = "Device activity history that Siri suggestions and Screen Time learn from."},
			{path = "/private/var/db/modelmanagerd", name = "Model manager", guard = "owner", feature = intelligence,
				what = "Bookkeeping for the on-device models Apple Intelligence loads."},
			{path = "/private/var/db/coreml", name = "Compiled Core ML models", guard = "owner",
				what = "Machine-learning models compiled for this Mac's Neural Engine. macOS rebuilds them."},
			{path = "/private/var/db/appinstalld", name = "App installer data", guard = "owner",
				what = "Records of the service that installs App Store apps."},
			{path = "/private/var/db/installcoordinationd", name = "Install coordination", guard = "owner",
				what = "Records of the service that coordinates app installs and updates."},
			{path = "/private/var/audit", name = "Security audit trail", guard = "owner", expected = true,
				what = "The BSM audit log of security events. macOS expires old trails."},
			{path = "/private/var/db/sysdiagnose/com.apple.sysdiagnose", name = "Diagnostics captures", guard = "owner",
				what = "System diagnoses you or Feedback Assistant captured. Each can be hundreds of megabytes; macOS removes old ones."},
		}},
	{id = "home", title = "Inside your home folder", icon = "house",
		summary = "Yours. Most hidden storage on a Mac is in ~/Library, which Finder hides.",
		locations = {
			{path = "~/Library/Caches", name = "Caches", expected = true, resource = "user-caches",
				what = "Data apps can download or rebuild. Clear a cache from the owning app."},
			{path = "~/Library/Application Support", name = "Application Support", expected = true, resource = "support",
				what = "Databases, downloads and state that apps cannot rebuild, including data of apps you deleted."},
			{path = "~/Library/Containers", name = "Containers", expected = true, resource = "app-containers",
				what = "Private homes of sandboxed apps, including most Apple apps. Deleting one resets that app."},
			{path = "~/Library/Group Containers", name = "Group Containers", expected = true, resource = "group-containers",
				what = "Data shared by related apps from one developer."},
			{path = "~/Library/Mobile Documents", name = "iCloud Drive", expected = true, guard = "privacy",
				what = "iCloud Drive and the iCloud data of apps. Files evicted to iCloud take no space here."},
			{path = "~/Library/Mail", name = "Mail", resource = "mail", guard = "privacy",
				what = "Local copies of your mailboxes and attachments."},
			{path = "~/Library/Messages", name = "Messages", resource = "messages", guard = "privacy",
				what = "Conversations and every attachment received, unless Messages is set to keep them only for a while."},
			{path = "~/Library/Logs", name = "Logs", expected = true, resource = "user-logs",
				what = "Your apps' logs and crash reports."},
			{path = "~/Library/Developer", name = "Developer",
				what = "Xcode's derived data, archives, device support and simulators."},
			{path = "~/Library/Biome", name = "Your activity streams", expected = true, guard = "privacy",
				what = "Your activity history for Siri suggestions and Screen Time."},
			{path = "~/Library/Trial", name = "Your Trial experiments", expected = true, guard = "privacy",
				what = "Per-account settings and small models for features Apple is tuning."},
			{path = "~/Library/iTunes/iPhone Software Updates", name = "iPhone updates", resource = "iphone-updates",
				what = "iOS versions Finder downloaded to update or restore an iPhone. Each is several gigabytes and is never needed again once the device is updated."},
			{path = "~/.Trash", name = "Trash", expected = true, resource = "user-trash", guard = "privacy",
				what = "Files you moved to the Trash. They take space until you empty it."},
		}},
	{id = "home-library", title = "Your Library, folder by folder", icon = "books.vertical.fill",
		summary = "The folders in ~/Library people most often ask about: who writes each and whether it may go.",
		locations = {
			{path = "~/Library/CloudStorage", name = "Cloud storage providers", expected = true,
				what = "Folders of Dropbox, Google Drive, OneDrive and other file provider apps. Files kept only online take no space; downloaded ones count fully. Free space from the provider's own app."},
			{path = "~/Library/Preferences", name = "Preferences", expected = true, resource = "preferences",
				what = "Every app's settings, one property list per app named by its bundle identifier. Small; deleting an app's file resets its settings."},
			{path = "~/Library/Saved Application State", name = "Saved window state", expected = true, resource = "saved-state",
				what = "The windows each app reopens when it launches. Safe to lose: the app only opens fresh."},
			{path = "~/Library/HTTPStorages", name = "Network storage", expected = true, resource = "http-storages",
				what = "Cookies and cached responses apps keep from their own network requests, a folder per app."},
			{path = "~/Library/WebKit", name = "Web view data", expected = true, resource = "webkit-data",
				what = "Website data such as local storage and caches of apps that show web pages inside their windows."},
			{path = "~/Library/LaunchAgents", name = "Your login agents", expected = true,
				what = "Background programs launchd starts when you log in, added by apps for your account only. Turn one off in System Settings › General › Login Items & Extensions; an agent of a deleted app is a leftover."},
			{path = "~/Library/Keychains", name = "Keychains", expected = true, owner = "Keychain Access",
				what = "Your passwords, keys and certificates. Never delete it: you would lose saved passwords."},
			{path = "~/Library/Fonts", name = "Your fonts", expected = true, owner = "Font Book",
				what = "Fonts installed for your account only. Manage them in Font Book."},
			{path = "~/Library/Daemon Containers", name = "Service containers", expected = true, guard = "privacy", owner = "macOS",
				what = "Private storage of macOS background services, each named by a random identifier. Only macOS manages them."},
			{path = "~/Library/Metadata/CoreSpotlight", name = "App content index", expected = true, guard = "privacy", owner = "Spotlight",
				what = "Spotlight's index of what apps such as Mail, Messages and Notes offer for search. A runaway index has reached tens of gigabytes; rebuild Spotlight's index instead of deleting it while you are logged in."},
			{path = "~/Library/Caches/com.apple.bird", name = "iCloud Drive cache", owner = "iCloud Drive",
				what = "Files iCloud Drive is uploading or downloading. It empties when sync finishes; if it stays large, turn iCloud Drive off and on in System Settings › [your name] › iCloud."},
			{path = "~/Library/Application Support/CloudDocs", name = "iCloud Drive database", expected = true, guard = "privacy", owner = "iCloud Drive",
				what = "iCloud Drive's record of what is synced. Never delete it; signing out of iCloud Drive and back in rebuilds it."},
			{path = "~/Library/Caches/CloudKit", name = "iCloud sync cache", guard = "privacy", owner = "iCloud",
				what = "Data apps sync through iCloud (CloudKit), cached by macOS. It is rebuilt from iCloud when needed."},
			{path = "~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches", name = "Photo analysis cache", owner = "Photos",
				what = "Work files of the service that recognizes faces, objects and text in your photos and videos. After a macOS update it can grow to tens of gigabytes while analysis runs, and it shrinks when analysis finishes."},
			{path = "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", name = "Mail attachments you opened", guard = "privacy", owner = "Mail",
				what = "Copies of attachments you opened from Mail. The originals stay in the messages, so the copies can go to the Trash once Mail is quit."},
			{path = "~/Library/Suggestions", name = "Siri suggestions", expected = true, guard = "privacy", owner = "Siri",
				what = "Contacts, events and other suggestions Siri finds in your mail and messages. macOS manages it."},
			{path = "~/Library/IdentityServices", name = "iMessage and FaceTime identity", expected = true, guard = "privacy", owner = "Messages",
				what = "The keys and registrations iMessage and FaceTime use. Never delete them."},
			{path = "~/Library/Accounts", name = "Internet accounts", expected = true, guard = "privacy", owner = "System Settings",
				what = "The accounts you added in System Settings › Internet Accounts for Mail, Contacts and Calendar."},
			{path = "~/Library/Safari", name = "Safari", expected = true, guard = "privacy", owner = "Safari",
				what = "Safari's history, bookmarks and Reading List. Clear history from Safari itself."},
			{path = "~/Library/Autosave Information", name = "Autosaved documents", expected = true, guard = "privacy",
				what = "Unsaved documents apps keep so they survive a crash or a quit. Save or close a document in its app to remove its copy."},
		}},
}

local byPath, byLeftover = {}, {}
for _, area in ipairs(Filesystem.areas) do
	for _, location in ipairs(area.locations) do
		location.area = area.id
		byPath[location.path] = location
		if location.leftover then byLeftover[location.leftover.id] = location end
	end
end

-- The location at `path`, or nil.
function Filesystem.find(path)
	return byPath[path]
end

-- The leftover location whose catalog id is `id`, or nil.
function Filesystem.leftover(id)
	return byLeftover[id]
end

-- Locations no app can read: the scan skips them.
function Filesystem.protected()
	local found = {}
	for _, area in ipairs(Filesystem.areas) do
		for _, location in ipairs(area.locations) do
			if location.guard == "sip" or location.guard == "owner" then table.insert(found, location) end
		end
	end
	return found
end

-- Locations measured by their APFS volume's own used space.
function Filesystem.volumes()
	local found = {}
	for _, area in ipairs(Filesystem.areas) do
		for _, location in ipairs(area.locations) do
			if location.volume then table.insert(found, location) end
		end
	end
	return found
end

return Filesystem
