-- Top-level sections that match macOS Storage. Paths are the documented
-- library locations; parent residuals exclude them, so sizes are not counted twice.
local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
local M = {}
function M.books()
	return group("books", "Books", "Books and audiobooks. Remove local copies in Books.", "book.fill", "systemOrange", {
		item("books-library", "Books library", "Downloaded books and audiobooks", "~/Library/Containers/com.apple.BKAgentService"),
	})
end
function M.icloud()
	return group("icloud-drive", "iCloud Drive", "Files stored in iCloud Drive. Cloud-only files are not downloaded.", "icloud.fill", "systemBlue", {
		item("icloud-docs", "iCloud Drive", "The iCloud Drive folder for this account", "~/Library/Mobile Documents/com~apple~CloudDocs"),
	})
end
function M.iosFiles()
	return group("ios-files", "iOS Files", "iPhone and iPad backups made by Finder", "iphone", "systemBlue", {
		item("device-backups", "iPhone & iPad backups", "Review connected-device backups in Finder", "~/Library/Application Support/MobileSync/Backup"),
		item("iphone-updates", "iPhone software updates", "Restore images Finder downloaded to update or restore an iPhone", "~/Library/iTunes/iPhone Software Updates", D.cache),
		item("ipad-updates", "iPad software updates", "Restore images Finder downloaded to update or restore an iPad", "~/Library/iTunes/iPad Software Updates", D.cache),
	})
end
function M.mail()
	return group("mail-library", "Mail", "Downloaded messages and attachments. Manage them in Mail.", "envelope.fill", "systemBlue", {
		item("mail", "Mailboxes", "Local mailboxes and downloaded messages", "~/Library/Mail"),
		item("mail-downloads", "Opened attachments", "Copies of attachments Mail saved when you opened them", "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", {policy = "Rebuildable", action = "trash", reviewThreshold = 500e6, consequence = "These are copies made when you opened an attachment; the original stays in its message and Mail copies it again on the next open. Quit Mail first. Moving to Trash does not free space until you empty it."}),
		item("mail-container", "Mail app data", "Sandboxed Mail data, excluding diagnostic logs", "~/Library/Containers/com.apple.mail"),
	})
end
function M.messages()
	return group("messages-library", "Messages", "Conversations and attachments. Manage them in Messages.", "message.fill", "systemGreen", {
		item("messages-attachments", "Message attachments", "Photos, videos and files received in conversations", "~/Library/Messages/Attachments", {action = "settings", reviewThreshold = 5e9, consequence = "Review large attachments in System Settings › General › Storage › Messages, or set Messages › Settings › General › Keep messages to one year. Deleting files here in Finder leaves broken conversations."}),
		item("messages", "Message history", "Conversations and the message index", "~/Library/Messages"),
		item("messages-container", "Messages app data", "Sandboxed Messages data", "~/Library/Containers/com.apple.MobileSMS"),
	})
end
function M.music()
	return group("music-library", "Music", "The Music library. GarageBand and Logic are under Music Creation.", "music.note", "systemRed", {
		item("music", "Music library", "Apple Music library and other audio in Music", "~/Music", {mediaAccess = true}),
	})
end
function M.musicCreation()
	return group("music-creation", "Music Creation", "GarageBand, Logic and shared Apple Loops", "pianokeys", "systemPink", {
		item("garageband", "GarageBand", "GarageBand projects and recordings", "~/Music/GarageBand"),
		item("logic", "Logic Pro", "Logic projects", "~/Music/Logic"),
		item("audio-music-apps", "Apple Loops & shared content", "Content shared by GarageBand and Logic", "~/Music/Audio Music Apps"),
	})
end
function M.podcasts()
	return group("podcasts", "Podcasts", "Downloaded episodes. Remove them in Podcasts.", "mic.fill", "systemPurple", {
		item("podcasts-library", "Podcasts library", "Downloaded podcast episodes", "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts"),
	})
end
function M.tv()
	return group("tv", "TV", "TV shows and other videos. Remove store downloads in TV.", "tv.fill", "systemGray", {
		item("tv-library", "TV library", "Shows and movies downloaded in TV", "~/Movies/TV", {mediaAccess = true}),
		item("movies", "Other videos", "Video files outside the TV library", "~/Movies", {mediaAccess = true}),
	})
end
function M.otherUsers()
	return group("other-users", "Other Users & Shared", "Other accounts on this Mac and the Shared folder", "person.2.fill", "systemGray", {
		item("users-other", "Other users & shared files", "Accessible files outside your home folder", "/Users"),
	})
end
return M
