-- The cleanup-assistance audit (#100): for every navigation destination, the
-- first useful conclusion it leads with and the next step it offers, or the
-- reason it has no cleanup action. tests/diskmap_issue100.test.lua checks that
-- every sidebar destination appears here, so a new page cannot ship without
-- an answer.
--
--   conclusion  what the page tells the reader first
--   next        where the reader goes from there (a page id, or an action)
--   none        why this page offers no cleanup action
return {
	overview = {conclusion = "Free space, scan coverage and a short ranked recovery plan.", next = "cleanup"},
	map = {conclusion = "Which categories and locations hold the space; selecting one explains ownership and eligibility.", next = "cleanup"},
	folder = {conclusion = "What fills any folder or disk, by folder, kind or last use; rows open their owner or move to the Trash where eligible.", next = "files"},
	largest = {conclusion = "The hundred largest measured locations, with the scope they cover stated beside the total.", next = "cleanup"},
	files = {conclusion = "Your own large and old files, installers kept apart from system images, generated build output never offered file by file.", next = "cleanup"},
	kinds = {conclusion = "Your installers and archives to review, with the total stored and the system-owned part stated apart; the chart follows.", next = "files"},
	duplicates = {conclusion = "Identical files in folders you choose, or why none are listed yet.", next = "cleanup"},
	basket = {conclusion = "The items you flagged, largest first, with what moving them to the Trash would recover; clear a flag to keep an item.", next = "review"},
	cleanup = {conclusion = "What Diskmap clears now, what each app clears, what a restart or the pending update clears, then your decisions, all ranked by eligible bytes, confidence and effort; system-managed storage is context only.", next = "review"},
	applications = {conclusion = "Leftover data of removed apps first, high confidence marked together; then apps with a known last use over six months. Unknown usage stays unknown.", next = "cleanup"},
	disks = {none = "Volumes and capacity are system-managed; Diskmap explains them and offers no removal."},
	updates = {none = "macOS updates, snapshots and staged installers are managed by macOS; the page explains what supported owner action helps and never suggests deleting protected system volumes; it routes to Clean Up with Clean Up's own estimate."},
	everyday = {conclusion = "Chat media, cloud downloads, offline media and Office data by app; each row names the app setting that reduces it.", next = "cleanup"},
	developer = {conclusion = "Developer storage by ecosystem with its rebuildable total; Simulators and Worktrees link into their review flows.", next = "simulators"},
	xcode = {conclusion = "Older device support and archives, with the newest version kept.", next = "cleanup"},
	projects = {conclusion = "Generated build output grouped by owning project, validated by marker files.", next = "cleanup"},
	simulators = {conclusion = "A minimal device set: keep one standard iPhone and one standard iPad, review the rest together.", next = "review"},
	worktrees = {conclusion = "Leftover Git worktrees that Git can remove, those needing review, and missing registrations.", next = "review"},
	music = {conclusion = "Sound libraries, plug-ins and projects by owner; libraries are removed in the app that installed them.", next = "cleanup"},
	video = {conclusion = "Render caches and proxies by app; libraries and projects are never offered.", next = "cleanup"},
	photography = {conclusion = "Photo libraries and caches by app; personal photos are never offered.", next = "cleanup"},
	design = {conclusion = "Design-tool caches and libraries by app.", next = "cleanup"},
	studio3d = {conclusion = "Engine caches and installed editors by tool.", next = "cleanup"},
	games = {conclusion = "Installed games and launchers, largest first; saved games are not offered.", next = "cleanup"},
	guide = {none = "Guidance only: it explains where macOS keeps things and links each topic to its measured location."},
	filesystem = {none = "Reference only: it maps macOS folders and marks the ones no app can read."},
	help = {none = "Help only: it documents Diskmap's own features."},
}
