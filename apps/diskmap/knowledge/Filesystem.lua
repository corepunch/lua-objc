-- A map of the macOS file system: every location worth knowing on a Mac
-- running macOS 26 or later, what it holds, who may read it and where
-- leftovers collect. It is plain data, read by helpers/Explain.lua so the
-- Folder Map and the System Data page can say what a folder is and whose,
-- and which locations no app can read.
--
-- Location fields:
--   path      exact path; "~" is the home folder
--   name      short name, as the page lists it
--   note      what it is in a few words, and whether it may go: the line
--             under its name wherever a folder list shows it
--   what      what it holds and how macOS uses it
--   guard     who may read it (see Filesystem.guards); nil when apps can
--   volume    APFS role whose own used space is the location's size
--   expected  present on every Mac of this macOS version
--   feature   what several locations serve together, named once
--   owner     the app or macOS service that writes it, as a person knows it
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
			{path = "/", name = "Macintosh HD", note = "macOS itself, sealed and read-only", volume = "System", expected = true,
				what = "The Signed System Volume: a sealed, read-only snapshot of macOS. Its size changes only with a macOS update."},
			{path = "/System/Volumes/Data", name = "Macintosh HD – Data", note = "Your files and everything apps write", volume = "Data", expected = true,
				what = "Everything that is yours and everything macOS writes at runtime. Firmlinks show its folders at the top of the disk."},
			{path = "/System/Volumes/Preboot", name = "Preboot", note = "Boot files and Safari for macOS · not junk", volume = "Preboot", expected = true,
				what = "Boot files, the FileVault unlock screen and the cryptexes that carry Safari and the shared code cache. It grows while an update is staged and shrinks once it installs. Its files are clones, so adding them up counts shared blocks several times; the volume's own size is the true one."},
			{path = "/System/Volumes/Recovery", name = "Recovery", note = "Reinstall and repair system · keep", volume = "Recovery", expected = true,
				what = "The recoveryOS used to reinstall macOS, restore from Time Machine or repair the disk. Usually not mounted; its size comes from APFS."},
			{path = "/System/Volumes/VM", name = "Swap", note = "Memory swapped to disk · a restart frees it", volume = "VM", expected = true,
				what = "Swap files macOS pages memory out to under memory pressure, and the sleep image on Intel Macs. Restarting releases swap."},
			{path = "/System/Volumes/Update", name = "Update", note = "Where macOS updates are prepared", volume = "Update", expected = true,
				what = "Where Software Update prepares a macOS update. A few hundred megabytes between updates; gigabytes while one is prepared or stuck."},
		}},
	{id = "preboot", title = "Inside Preboot", icon = "power",
		summary = "The volume the Mac starts from before macOS itself is unlocked. All of it is macOS's; none of it is junk an update forgot.",
		locations = {
			{path = "/System/Volumes/Preboot/Cryptexes", name = "Cryptexes", note = "Safari, system code and Rosetta · macOS's", expected = true,
				what = "Cryptexes are sealed disk images macOS mounts at startup over /System/Cryptexes. Keeping Safari, the shared code cache and Rosetta in them lets Apple patch those parts with a Rapid Security Response instead of a full update. macOS manages them; nothing here can be removed by hand."},
			{path = "/System/Volumes/Preboot/Cryptexes/OS", name = "OS cryptex", note = "System libraries every app loads · macOS's", expected = true,
				what = "The shared code cache: every system library, prelinked into one file so apps start quickly. Each macOS version brings its own."},
			{path = "/System/Volumes/Preboot/Cryptexes/App", name = "App cryptex", note = "Safari and WebKit · macOS's", expected = true,
				what = "Safari and the WebKit engine, kept apart so security fixes for the browser reach you without a full macOS update."},
			{path = "/System/Volumes/Preboot/Cryptexes/Rosetta", name = "Rosetta cryptex", note = "Rosetta for Intel apps · macOS's",
				what = "Rosetta and the Intel versions of system libraries that Intel apps load on Apple silicon. It is present once Rosetta is installed and goes away only with it."},
			{path = "/System/Volumes/Preboot/Cryptexes/Incoming", name = "Incoming cryptexes", note = "The next update's cryptexes, staged",
				what = "The cryptexes of an update or Rapid Security Response that is downloaded and waiting to install. macOS swaps them in at the next restart into the update; a stalled update keeps them here until it installs or is cancelled."},
			{path = "/System/Volumes/Preboot/staging", name = "Preboot staging", note = "Update staging · empty between updates", expected = true,
				what = "Where an update prepares boot files. Empty between updates."},
		}},
	{id = "top", title = "The top of the disk", icon = "folder",
		summary = "What Finder shows at the top of Macintosh HD, and the hidden Unix folders beside it.",
		locations = {
			{path = "/Applications", name = "Applications", note = "Apps installed for everyone", expected = true,
				what = "Apps installed for everyone. Apple's own apps live on the sealed system volume at /System/Applications and only appear here."},
			{path = "/System/Applications", name = "Apple apps", note = "Apps that ship with macOS · can't be removed", expected = true,
				what = "Safari, Mail, Music and the other apps that ship with macOS. They are part of the sealed system and cannot be removed."},
			{path = "/Users", name = "Users", note = "Every account's home folder", expected = true,
				what = "A home folder for every account, and Shared for files every account can reach."},
			{path = "/Users/Shared", name = "Shared", note = "Files every account can reach", expected = true,
				what = "Files meant for every account. Installers of music and creative apps sometimes leave large sample libraries here."},
			{path = "/Library", name = "Library", note = "Fonts, drivers and app data for everyone", expected = true,
				what = "Resources shared by every account: fonts, drivers, caches, app support installed by administrators."},
			{path = "/System", name = "System", note = "macOS itself · protected", expected = true,
				what = "macOS itself, on the sealed read-only volume, plus firmlinked folders such as AssetsV2 that live on the Data volume."},
			{path = "/usr", name = "usr", note = "Unix tools that ship with macOS", expected = true,
				what = "Unix commands and libraries. /usr/local is the one part that belongs to you: tools installed outside the App Store."},
			{path = "/usr/local", name = "usr/local", note = "Command-line tools you installed",
				what = "Command-line tools you or an installer added, including Homebrew on Intel Macs."},
			{path = "/opt/homebrew", name = "Homebrew", note = "Homebrew packages",
				what = "Homebrew's packages on Apple silicon."},
			{path = "/private", name = "private", note = "macOS working data, logs and temp files", expected = true,
				what = "Where /etc, /tmp and /var really live. macOS keeps its working data, logs and databases here."},
			{path = "/cores", name = "Core dumps", note = "Crash memory dumps · safe to remove", expected = true,
				what = "Memory images written when a process crashes with core dumps enabled. Normally empty; a single dump can take gigabytes."},
			{path = "/macOS Install Data", name = "macOS Install Data", note = "Leftover of a macOS install · see Clean Up",
				what = "Staging for a macOS installation started from an Install macOS app. It is removed when the installation finishes; one left behind is an interrupted install."},
		}},
	{id = "data-hidden", title = "Hidden at the top of the Data volume", icon = "eye.slash",
		summary = "Volume-wide databases macOS keeps out of sight. Most are readable only by macOS itself.",
		locations = {
			{path = "/System/Volumes/Data/.Spotlight-V100", name = "Spotlight index", note = "Spotlight search index · rebuilt by macOS", guard = "owner", expected = true,
				what = "The search index for the Data volume. It grows with the number of files and mail messages. Rebuild it by adding the disk to Spotlight's privacy list and removing it again."},
			{path = "/System/Volumes/Data/.fseventsd", name = "File change log", note = "File change log · trimmed by macOS", guard = "owner", expected = true,
				what = "The record of file changes that Time Machine, Spotlight and sync apps read. macOS trims it on its own."},
			{path = "/System/Volumes/Data/.DocumentRevisions-V100", name = "Document versions", note = "Earlier versions of your documents", guard = "owner", expected = true,
				what = "Earlier versions of documents that apps save with Versions. Large edited files keep large histories. Manage them from File › Revert To in the app."},
			{path = "/System/Volumes/Data/.PreviousSystemInformation", name = "Previous system information", note = "Details of the previous macOS version", expected = true,
				what = "Details of the macOS version before the last update, kept for Migration and diagnostics."},
			{path = "/System/Volumes/Data/MobileSoftwareUpdate", name = "Update staging (Data)", note = "Update staging · gigabytes mean a stuck update",
				what = "Where macOS unpacks parts of an update on the Data volume. Normally a few megabytes; gigabytes mean an update is prepared or was interrupted."},
		}},
	{id = "system", title = "Inside /System", icon = "gearshape.2",
		summary = "The operating system. Only the asset store changes between updates.",
		locations = {
			{path = "/System/Library/AssetsV2", name = "Downloaded system assets", note = "Models, voices and updates macOS downloaded", expected = true,
				what = "The MobileAsset store: models, voices, fonts, dictionaries, wallpapers and software updates macOS downloads when a feature needs them. It lives on the Data volume through a firmlink."},
			{path = assets .. "UAF_FM_GenerativeModels", name = "Apple Intelligence language model", note = "Apple Intelligence model · on-device", guard = "sip", feature = intelligence,
				what = "The on-device foundation model behind Writing Tools, summaries and Siri. Several gigabytes when Apple Intelligence is on."},
			{path = assets .. "UAF_FM_Visual", name = "Apple Intelligence visual model", note = "Apple Intelligence image model", guard = "sip", feature = intelligence,
				what = "The on-device model that understands images, used by Image Playground and visual look-up."},
			{path = assets .. "UAF_FM_CodeLM", name = "Apple Intelligence coding model", note = "Xcode code-completion model", guard = "sip", feature = intelligence,
				what = "The on-device model behind predictive code completion in Xcode."},
			{path = assets .. "UAF_FM_Overrides", name = "Apple Intelligence model updates", note = "Apple Intelligence model updates", guard = "sip", feature = intelligence,
				what = "Adapters and updates applied on top of the foundation models."},
			{path = assets .. "UAF_IF_Planner", name = "Apple Intelligence planner", note = "Siri's request planner model", guard = "sip", feature = intelligence,
				what = "The model that plans multi-step requests for Siri and App Intents."},
			{path = assets .. "UAF_IF_PlannerOverrides", name = "Apple Intelligence planner updates", note = "Siri planner model updates", guard = "sip", feature = intelligence,
				what = "Updates applied on top of the planner model."},
			{path = assets .. "MacSoftwareUpdate", name = "Downloaded macOS updates", note = "Downloaded macOS update · install to clear",
				what = "Update payloads Software Update downloaded. A paused, deferred or failed download stays here until macOS installs, retries or purges it."},
			{path = "/System/Library/AssetsV2/PreinstalledAssetsV2", name = "Preinstalled assets", note = "Assets that shipped with macOS", expected = true,
				what = "Assets that shipped with macOS and are replaced as newer versions download."},
			{path = "/System/Cryptexes", name = "Cryptexes", note = "Preboot's cryptexes, mounted · no space here", expected = true,
				what = "Mount points for the cryptexes stored in Preboot: Safari, the shared code cache and Rapid Security Responses. Their space counts in Preboot."},
			{path = "/System/Library/Speech", name = "Speech", note = "Built-in voices and speech engines", expected = true,
				what = "Speech engines and voices that ship with macOS."},
		}},
	{id = "library", title = "Inside /Library", icon = "books.vertical",
		summary = "Shared by every account on this Mac. Installers and administrators write here.",
		locations = {
			{path = "/Library/Caches", name = "Shared caches", note = "Shared caches · rebuilt by macOS", expected = true,
				what = "Caches of system services and apps installed for everyone. macOS rebuilds them."},
			{path = "/Library/Logs", name = "Shared logs", note = "Diagnostic and install logs", expected = true,
				what = "Diagnostic reports, install logs and logs of system-wide apps."},
			{path = "/Library/Application Support", name = "Shared application support", note = "Data of apps installed for everyone", expected = true,
				what = "Data of apps installed for every account, license files, plug-in content and sound libraries."},
			{path = "/Library/Application Support/com.apple.idleassetsd/Customer", name = "Aerial wallpapers", note = "Downloaded Aerial wallpapers",
				what = "Aerial screen savers and wallpapers you downloaded in Wallpaper settings. Each is hundreds of megabytes; remove them from Wallpaper settings."},
			{path = "/Library/Developer", name = "Shared developer tools", note = "Command Line Tools and simulator runtimes",
				what = "Command Line Tools and simulator runtimes shared by every account."},
			{path = "/Library/Updates", name = "Legacy updates", note = "Pre-Big Sur updates · large means leftover", expected = true,
				what = "Where macOS put updates before Big Sur. Today it holds only a small index; anything large here is a leftover from an old update."},
			{path = "/Library/Trial", name = "Trial experiments", note = "Settings macOS tests for Apple · tiny", expected = true, guard = "privacy",
				what = "Settings and small models macOS downloads for features being tuned by Apple."},
			{path = "/Library/Audio", name = "Audio", note = "Audio plug-ins and GarageBand/Logic sounds", expected = true,
				what = "Audio drivers, plug-ins and sound libraries. GarageBand and Logic add gigabytes of instruments to Apple Loops here."},
			{path = "/Library/Fonts", name = "Shared fonts", note = "Fonts for every account", expected = true,
				what = "Fonts installed for every account."},
			{path = "/Library/Receipts", name = "Installer receipts", note = "Records of installed packages · small", expected = true,
				what = "Records of packages installed with the Installer. Small."},
			{path = "/Library/LaunchAgents", name = "Login agents for everyone", note = "Login programs for every account", expected = true,
				what = "Background programs launchd starts for every account at login, added by installers. Each property list names the program it runs. Turn one off in System Settings › General › Login Items & Extensions; remove it with the app that installed it."},
			{path = "/Library/LaunchDaemons", name = "Startup daemons", note = "Programs started before login", expected = true,
				what = "Background programs launchd starts at startup, before anyone logs in, added by installers such as VPN, backup and driver software. Remove one with the app that installed it."},
			{path = "/Library/PrivilegedHelperTools", name = "Privileged helpers", note = "Admin helpers apps installed", expected = true,
				what = "Programs apps installed to run as an administrator, such as Docker's network helper. A helper stays after its app is dragged to the Trash; the app's own uninstaller removes it."},
			{path = "/Library/Application Support/Apple/AssetCache/Data", name = "Content Caching", note = "Content Caching for other Apple devices", owner = "Content Caching",
				what = "Software updates, apps and iCloud data this Mac caches for other Apple devices on the network when Content Caching is on in System Settings › General › Sharing. Tools that fill it ahead of time are often called “precache”. Clear it with Reset in Content Caching's options (the ⓘ button beside it in Sharing), or turn Content Caching off."},
		}},
	{id = "var", title = "Inside /private/var", icon = "cylinder.split.1x2",
		summary = "macOS's own working data: temporary files, logs and service databases.",
		locations = {
			{path = "/private/var/folders", name = "Per-user temporary files", note = "Temporary files and system caches", expected = true,
				what = "Each account's $TMPDIR and system caches such as Quick Look thumbnails and App Store downloads. Restarting clears stale temporary files."},
			{path = "/private/tmp", name = "tmp", note = "Temporary files · emptied at restart", expected = true,
				what = "Temporary files of command-line tools and installers; /tmp is a link to it. macOS empties it at every restart."},
			{path = "/private/var/tmp", name = "var/tmp", note = "Temporary files kept across restarts", expected = true,
				what = "Temporary files meant to survive a restart. macOS removes old ones periodically."},
			{path = "/private/var/log", name = "System logs", note = "Unix service logs · rotated by macOS", expected = true,
				what = "Text logs of Unix services and installs. macOS rotates them."},
			{path = "/private/var/db/diagnostics", name = "Unified log", note = "System log Console reads · size-capped", expected = true,
				what = "The system log Console reads. macOS keeps it to a size budget and removes old entries."},
			{path = "/private/var/db/uuidtext", name = "Unified log strings", note = "Strings the system log refers to", expected = true,
				what = "Format strings the unified log refers to. It grows and shrinks with the log."},
			{path = "/private/var/db/powerlog", name = "Power log", note = "Battery and energy history", expected = true,
				what = "Battery and energy history behind Battery settings. macOS trims it."},
			{path = "/private/var/db/receipts", name = "Package receipts", note = "Bills of materials of installed packages", expected = true,
				what = "Bills of materials for packages installed with the Installer, used to update or verify them."},
			{path = "/private/var/db/softwareupdate", name = "Software Update data", note = "Software Update records", expected = true,
				what = "Software Update's own records and catalogs."},
			{path = "/private/var/db/com.apple.xpc.roleaccountd.staging", name = "App install staging", note = "App install staging · cleared by macOS", guard = "sip", expected = true,
				what = "Where the App Store and installers stage an app before moving it into place. A download interrupted mid-install can leave data here until macOS cleans it up; restarting and reopening the App Store lets it finish or discard it."},
			{path = "/private/var/install", name = "macOS install staging", note = "macOS install staging · removed when done", guard = "sip",
				what = "Staging for a macOS installation in progress. macOS removes it when the installation completes or is abandoned."},
			{path = "/private/var/MobileSoftwareUpdate", name = "Update brain", note = "Software Update engine · replaced each update", expected = true,
				what = "The Software Update engine macOS downloads for each update."},
			{path = "/private/var/db/oah", name = "Rosetta translations", note = "Intel apps translated by Rosetta · rebuilt", guard = "sip",
				what = "Intel apps translated for Apple silicon by Rosetta. Grows with every Intel app you run; macOS rebuilds it."},
			{path = "/private/var/db/KernelExtensionManagement/Staging", name = "Staged system extensions", note = "Extensions waiting for approval", guard = "sip",
				what = "Kernel and system extensions waiting for approval or a restart."},
			{path = "/private/var/db/Spotlight-V100", name = "System Spotlight index", note = "Spotlight index of system locations", guard = "owner", expected = true,
				what = "Spotlight's index for system locations."},
			{path = "/private/var/db/fseventsd", name = "System file change log", note = "File change log of the system", guard = "owner", expected = true,
				what = "File change records for the system volume."},
			{path = "/private/var/db/biome", name = "Activity streams", note = "Activity history for Siri and Screen Time", guard = "owner", expected = true,
				what = "Device activity history that Siri suggestions and Screen Time learn from."},
			{path = "/private/var/db/modelmanagerd", name = "Model manager", note = "Apple Intelligence model bookkeeping", guard = "owner", feature = intelligence,
				what = "Bookkeeping for the on-device models Apple Intelligence loads."},
			{path = "/private/var/db/coreml", name = "Compiled Core ML models", note = "Machine-learning models compiled for this Mac", guard = "owner",
				what = "Machine-learning models compiled for this Mac's Neural Engine. macOS rebuilds them."},
			{path = "/private/var/db/appinstalld", name = "App installer data", note = "App Store install records", guard = "owner",
				what = "Records of the service that installs App Store apps."},
			{path = "/private/var/db/installcoordinationd", name = "Install coordination", note = "App install coordination records", guard = "owner",
				what = "Records of the service that coordinates app installs and updates."},
			{path = "/private/var/audit", name = "Security audit trail", note = "Security event log · expires by itself", guard = "owner", expected = true,
				what = "The BSM audit log of security events. macOS expires old trails."},
			{path = "/private/var/db/sysdiagnose/com.apple.sysdiagnose", name = "Diagnostics captures", note = "System diagnoses · removed by macOS", guard = "owner",
				what = "System diagnoses you or Feedback Assistant captured. Each can be hundreds of megabytes; macOS removes old ones."},
		}},
	{id = "home", title = "Inside your home folder", icon = "house",
		summary = "Yours. Most hidden storage on a Mac is in ~/Library, which Finder hides.",
		locations = {
			{path = "~/Library/Caches", name = "Caches", note = "Apps' caches · rebuilt when needed", expected = true,
				what = "Data apps can download or rebuild. Clear a cache from the owning app."},
			{path = "~/Library/Application Support", name = "Application Support", note = "Apps' data, including removed apps'", expected = true,
				what = "Databases, downloads and state that apps cannot rebuild, including data of apps you deleted."},
			{path = "~/Library/Containers", name = "Containers", note = "Sandboxed apps' private data", expected = true,
				what = "Private homes of sandboxed apps, including most Apple apps. Deleting one resets that app."},
			{path = "~/Library/Group Containers", name = "Group Containers", note = "Data shared by one developer's apps", expected = true,
				what = "Data shared by related apps from one developer."},
			{path = "~/Library/Mobile Documents", name = "iCloud Drive", note = "iCloud Drive and apps' iCloud data", expected = true, guard = "privacy",
				what = "iCloud Drive and the iCloud data of apps. Files evicted to iCloud take no space here."},
			{path = "~/Library/Mail", name = "Mail", note = "Your mailboxes and attachments", guard = "privacy",
				what = "Local copies of your mailboxes and attachments."},
			{path = "~/Library/Messages", name = "Messages", note = "Your conversations and attachments", guard = "privacy",
				what = "Conversations and every attachment received, unless Messages is set to keep them only for a while."},
			{path = "~/Library/Logs", name = "Logs", note = "Apps' logs and crash reports", expected = true,
				what = "Your apps' logs and crash reports."},
			{path = "~/Library/Developer", name = "Developer", note = "Xcode builds, archives and simulators",
				what = "Xcode's derived data, archives, device support and simulators."},
			{path = "~/Library/Biome", name = "Your activity streams", note = "Your activity history for Siri", expected = true, guard = "privacy",
				what = "Your activity history for Siri suggestions and Screen Time."},
			{path = "~/Library/Trial", name = "Your Trial experiments", note = "Settings macOS tests for Apple · tiny", expected = true, guard = "privacy",
				what = "Per-account settings and small models for features Apple is tuning."},
			{path = "~/Library/iTunes/iPhone Software Updates", name = "iPhone updates", note = "Old iPhone updates · safe to remove",
				what = "iOS versions Finder downloaded to update or restore an iPhone. Each is several gigabytes and is never needed again once the device is updated."},
			{path = "~/.Trash", name = "Trash", note = "Files you deleted · empty the Trash", expected = true, guard = "privacy",
				what = "Files you moved to the Trash. They take space until you empty it."},
		}},
	{id = "home-library", title = "Your Library, folder by folder", icon = "books.vertical.fill",
		summary = "The folders in ~/Library people most often ask about: who writes each and whether it may go.",
		locations = {
			{path = "~/Library/CloudStorage", name = "Cloud storage providers", note = "Dropbox, Google Drive, OneDrive files", expected = true,
				what = "Folders of Dropbox, Google Drive, OneDrive and other file provider apps. Files kept only online take no space; downloaded ones count fully. Free space from the provider's own app."},
			{path = "~/Library/Preferences", name = "Preferences", note = "Every app's settings · small", expected = true,
				what = "Every app's settings, one property list per app named by its bundle identifier. Small; deleting an app's file resets its settings."},
			{path = "~/Library/Saved Application State", name = "Saved window state", note = "Windows apps reopen · safe to remove", expected = true,
				what = "The windows each app reopens when it launches. Safe to lose: the app only opens fresh."},
			{path = "~/Library/HTTPStorages", name = "Network storage", note = "Apps' cookies and network caches", expected = true,
				what = "Cookies and cached responses apps keep from their own network requests, a folder per app."},
			{path = "~/Library/WebKit", name = "Web view data", note = "Web data of apps that show web pages", expected = true,
				what = "Website data such as local storage and caches of apps that show web pages inside their windows."},
			{path = "~/Library/LaunchAgents", name = "Your login agents", note = "Programs started at your login", expected = true,
				what = "Background programs launchd starts when you log in, added by apps for your account only. Turn one off in System Settings › General › Login Items & Extensions; an agent of a deleted app is a leftover."},
			{path = "~/Library/Keychains", name = "Keychains", note = "Your passwords · never delete", expected = true, owner = "Keychain Access",
				what = "Your passwords, keys and certificates. Never delete it: you would lose saved passwords."},
			{path = "~/Library/Fonts", name = "Your fonts", note = "Fonts for your account", expected = true, owner = "Font Book",
				what = "Fonts installed for your account only. Manage them in Font Book."},
			{path = "~/Library/Daemon Containers", name = "Service containers", note = "macOS services' private storage", expected = true, guard = "privacy", owner = "macOS",
				what = "Private storage of macOS background services, each named by a random identifier. Only macOS manages them."},
			{path = "~/Library/Metadata/CoreSpotlight", name = "App content index", note = "Spotlight index of app content", expected = true, guard = "privacy", owner = "Spotlight",
				what = "Spotlight's index of what apps such as Mail, Messages and Notes offer for search. A runaway index has reached tens of gigabytes; rebuild Spotlight's index instead of deleting it while you are logged in."},
			{path = "~/Library/Caches/com.apple.bird", name = "iCloud Drive cache", note = "iCloud Drive transfers in progress", owner = "iCloud Drive",
				what = "Files iCloud Drive is uploading or downloading. It empties when sync finishes; if it stays large, turn iCloud Drive off and on in System Settings › [your name] › iCloud."},
			{path = "~/Library/Application Support/CloudDocs", name = "iCloud Drive database", note = "iCloud Drive's sync database · keep", expected = true, guard = "privacy", owner = "iCloud Drive",
				what = "iCloud Drive's record of what is synced. Never delete it; signing out of iCloud Drive and back in rebuilds it."},
			{path = "~/Library/Caches/CloudKit", name = "iCloud sync cache", note = "iCloud sync cache · rebuilt from iCloud", guard = "privacy", owner = "iCloud",
				what = "Data apps sync through iCloud (CloudKit), cached by macOS. It is rebuilt from iCloud when needed."},
			{path = "~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches", name = "Photo analysis cache", note = "Photo analysis work files · shrinks later", owner = "Photos",
				what = "Work files of the service that recognizes faces, objects and text in your photos and videos. After a macOS update it can grow to tens of gigabytes while analysis runs, and it shrinks when analysis finishes."},
			{path = "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", name = "Mail attachments you opened", note = "Mail attachments you opened · copies", guard = "privacy", owner = "Mail",
				what = "Copies of attachments you opened from Mail. The originals stay in the messages, so the copies can go to the Trash once Mail is quit."},
			{path = "~/Library/Suggestions", name = "Siri suggestions", note = "Siri suggestions from mail and messages", expected = true, guard = "privacy", owner = "Siri",
				what = "Contacts, events and other suggestions Siri finds in your mail and messages. macOS manages it."},
			{path = "~/Library/IdentityServices", name = "iMessage and FaceTime identity", note = "iMessage and FaceTime keys · keep", expected = true, guard = "privacy", owner = "Messages",
				what = "The keys and registrations iMessage and FaceTime use. Never delete them."},
			{path = "~/Library/Accounts", name = "Internet accounts", note = "Internet accounts for Mail and Calendar", expected = true, guard = "privacy", owner = "System Settings",
				what = "The accounts you added in System Settings › Internet Accounts for Mail, Contacts and Calendar."},
			{path = "~/Library/Safari", name = "Safari", note = "Safari history, bookmarks and Reading List", expected = true, guard = "privacy", owner = "Safari",
				what = "Safari's history, bookmarks and Reading List. Clear history from Safari itself."},
			{path = "~/Library/Autosave Information", name = "Autosaved documents", note = "Unsaved documents' backups", expected = true, guard = "privacy",
				what = "Unsaved documents apps keep so they survive a crash or a quit. Save or close a document in its app to remove its copy."},
		}},
}

local byPath = {}
for _, area in ipairs(Filesystem.areas) do
	for _, location in ipairs(area.locations) do
		location.area = area.id
		byPath[location.path] = location
	end
end

-- The location at `path`, or nil.
function Filesystem.find(path)
	return byPath[path]
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
