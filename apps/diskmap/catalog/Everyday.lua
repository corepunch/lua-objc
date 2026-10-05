-- The apps most people use every day: messaging, cloud sync, downloads for
-- offline listening and watching, Office and the browser. Their media piles
-- up out of sight in ~/Library, often larger than anything a developer
-- keeps. Paths are each product's default location; the Everyday page
-- (knowledge/Workflows.lua) presents this group.
local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
-- Chat media is often the only copy of a photo or video someone sent, so it
-- is reviewed in the app, never offered as a cache.
local function chat(owner, where)
	return {reviewThreshold = 2e9, consequence = "Photos, videos and files from your chats. Review them in " .. owner .. (where and (" (" .. where .. ")") or "") .. "; a chat's media may be the only copy you have."}
end
local function offline(owner, where)
	return {reviewThreshold = 2e9, consequence = "Downloads for offline use. Remove the ones you have finished in " .. owner .. " (" .. where .. "); they download again when you want them."}
end
return function()
	return group("everyday", "Everyday Apps", "Messaging, cloud sync, offline downloads, Office and the browser", "bubble.left.and.bubble.right.fill", "systemCyan", {
		group("messaging", "Messaging & calls", "Chat history and the photos, videos and files people sent you", "bubble.left.fill", "systemGreen", {
			item("whatsapp", "WhatsApp", "Chat history and media", "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared",
				chat("WhatsApp", "Settings › Storage and Data › Manage Storage")),
			item("telegram", "Telegram", "Chat history and downloaded media", "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram",
				{reviewThreshold = 2e9, consequence = "Media you opened is kept on this Mac; it stays available in the chat. Clear it in Telegram › Settings › Data and Storage › Storage Usage, where its size limit is set too."}),
			item("telegram-desktop", "Telegram Desktop", "Downloaded media and cache of the desktop version", "~/Library/Application Support/Telegram Desktop",
				{reviewThreshold = 2e9, consequence = "Clear it in Telegram Desktop › Settings › Advanced › Manage Local Storage. Media stays available in the chat."}),
			item("signal", "Signal", "Message history and attachments", "~/Library/Application Support/Signal",
				chat("Signal", "Settings › Chats")),
			item("wechat", "WeChat", "Chat history and media", "~/Library/Containers/com.tencent.xinWeChat",
				chat("WeChat", "Settings › Storage")),
			item("zoom-recordings", "Zoom recordings", "Meetings recorded to this Mac", "~/Documents/Zoom",
				{reviewThreshold = 2e9, consequence = "Your own recordings: no other copy exists unless you made one. Move old ones to another disk or delete them in the Finder."}),
		}),
		group("cloud-sync", "Cloud sync", "Files kept downloaded by Dropbox, Google Drive, OneDrive and other providers", "icloud.and.arrow.down.fill", "systemBlue", {
			-- Online-only files take no space, so the measured size is what is downloaded.
			item("cloud-storage", "Cloud storage folders", "Downloaded files of Dropbox, Google Drive, OneDrive and Box", "~/Library/CloudStorage",
				{reviewThreshold = 5e9, consequence = "Only downloaded files take space. Control-click files or folders in the Finder and choose Remove Download: they stay in your cloud storage and download again when opened."}),
			item("google-drive-cache", "Google Drive cache", "Files Google Drive keeps on this Mac for its stream", "~/Library/Application Support/Google/DriveFS",
				{reviewThreshold = 2e9, consequence = "Google Drive manages this cache. Set its location and offline files in Google Drive › Settings; quit Google Drive before changing anything here."}),
		}),
		group("offline-media", "Offline media", "Music, videos, books and recordings downloaded to this Mac", "arrow.down.circle.fill", "systemPink", {
			item("spotify-downloads", "Spotify downloads", "Songs and podcasts downloaded for offline listening", "~/Library/Application Support/Spotify/PersistentCache",
				offline("Spotify", "Settings › Storage")),
			item("prime-video", "Prime Video", "Movies and episodes downloaded to watch offline", "~/Library/Containers/com.amazon.aiv.AIVApp",
				offline("Prime Video", "Downloads")),
			item("kindle", "Kindle", "Downloaded books", "~/Library/Containers/com.amazon.Lassen",
				offline("Kindle", "Library › Downloaded")),
			item("voice-memos", "Voice Memos", "Your recordings", "~/Library/Group Containers/group.com.apple.VoiceMemos.shared",
				{consequence = "Your own recordings. Delete old ones in Voice Memos, then empty its Recently Deleted."}),
		}),
		group("office", "Microsoft Office", "Word, Excel, PowerPoint and Outlook data", "doc.richtext.fill", "systemOrange", {
			item("office-shared", "Office shared data", "Fonts, templates, caches and settings shared by the Office apps", "~/Library/Group Containers/UBF8T346G9.Office",
				{consequence = "Shared by every Office app. Remove Office with its own uninstaller; removing this folder resets Office."}),
			item("outlook", "Outlook mail & calendars", "Local copies of your mailboxes and calendars", "~/Library/Group Containers/UBF8T346G9.Office/Outlook",
				{reviewThreshold = 5e9, consequence = "Outlook keeps a copy of your mail here and downloads it again from the server. Reduce it in Outlook › Settings › Accounts by syncing less mail."}),
		}),
		group("browser-data", "Browser data", "Profiles and downloaded features of the browser, apart from its cache", "globe", "systemIndigo", {
			item("chrome-profiles", "Google Chrome profiles", "History, extensions, site data and settings", "~/Library/Application Support/Google/Chrome",
				{consequence = "Your browsing profiles. Remove site data and unused profiles in Chrome's settings."}),
			item("chrome-ai-model", "Chrome on-device AI model", "A language model Chrome downloads for its AI features", "~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel",
				{reviewThreshold = 1e9, consequence = "Chrome downloads this model again while its on-device AI features are on. Turn them off in Chrome › Settings › System to keep it removed."}),
		}),
	})
end
