-- What people do with a Mac, and the storage each kind of work builds up.
-- One entry is one sidebar page: sections of catalog locations, largest
-- first. A page appears only on a Mac that has its data, so a musician sees
-- Music Production and never Xcode.
--
--   id                      the page's id in app.xml, which owns its sidebar row,
--                           header, icon, color, section and shortcut
--   noun                    "Measuring <noun>…", "No <noun> found"
--   summary                 follows the total: "12.4 GB across …"
--   empty                   what the page will show, while it has nothing
--   footnote                the page's promise about what Diskmap leaves alone
--   markers                 paths whose presence alone shows the page
--   visibleBytes            measured size that shows the page without a marker
--   links                   header buttons: {title, open = resource or page id}
--   sections                {id, title, detail, groups, roots, items}:
--     groups   catalog groups whose children are the rows; a nested group
--              rolls up into one row that opens its own list
--     roots    groups whose direct locations only are rows
--     items    single locations, wherever the catalog keeps them
--
-- A location may appear on more than one page (Adobe's caches matter to
-- video and to design work); each page totals what it shows. The catalog
-- (catalog/*.lua) stays the one place that says where data lives.
local Workflows = {}

Workflows.visibleBytes = 500e6

Workflows.list = {
	{id = "developer",
		noun = "developer storage", summary = "across Xcode, packages, containers and AI tools",
		empty = "Xcode, package managers, containers and AI tools appear here once measured.",
		footnote = "Diskmap never removes simulator runtimes, SDKs or archives on its own. Rebuildable data is moved to the Trash only after you review it.",
		markers = {"~/Library/Developer", "/Applications/Xcode.app"},
		links = {{title = "Simulators…", open = "simulators"}, {title = "Worktrees…", page = "worktrees"}},
		sections = {
			{id = "xcode", title = "Xcode & simulators", detail = "Build data, device support and simulators. Runtimes and SDKs are managed by Xcode.", groups = {"xcode"}},
			{id = "packages", title = "Packages & toolchains", detail = "Download caches refill on demand; installed toolchains are removed with their version manager.", groups = {"packages", "toolchains", "test-browsers", "mobile-dev"}},
			{id = "projects", title = "Projects & editors", detail = "Source, generated project folders and editor data. Review before removing anything here.", roots = {"developer"}, groups = {"editors"}},
			{id = "containers", title = "Containers & virtual machines", detail = "Prune from the owning tool. Virtual disks can hold databases and personal work.", groups = {"containers"}},
			{id = "ai", title = "AI tools & models", detail = "Coding-agent caches are separated from sessions and worktrees; model weights download again.", groups = {"ai-tools", "local-models"}},
		}},
	{id = "music",
		noun = "music production storage", summary = "across sound libraries, instruments, plug-ins and projects",
		empty = "Logic, GarageBand, Ableton Live, sample libraries and audio plug-ins appear here once measured.",
		footnote = "Sound libraries are removed in the app that installed them, which keeps its instruments working. Diskmap never deletes projects, samples or plug-ins.",
		markers = {"/Applications/Logic Pro.app", "/Applications/MainStage.app", "~/Music/Ableton", "/Library/Application Support/Logic"},
		sections = {
			{id = "apple", title = "GarageBand & Logic", detail = "Projects, and the sound libraries these apps download. Remove unused library content in the app's Sound Library.", groups = {"apple-music-apps"}},
			{id = "libraries", title = "Instruments & sample libraries", detail = "Often the largest part of a studio. Libraries are removed, or moved to another disk, with their maker's own tool.", groups = {"sample-libraries"}},
			{id = "plugins", title = "Plug-ins & shared audio", detail = "Audio Units, VST and AAX plug-ins with their presets. Projects need the plug-ins they were made with.", groups = {"audio-plugins"}},
		}},
	{id = "video",
		noun = "video production storage", summary = "across libraries, render caches and proxies",
		empty = "Final Cut Pro, iMovie, DaVinci Resolve and Adobe video data appear here once measured.",
		footnote = "Render files and proxies are recreated only while their source media is available. Delete them in the app that made them; Diskmap never removes libraries or projects.",
		markers = {"/Applications/Final Cut Pro.app", "/Applications/DaVinci Resolve", "/Applications/Adobe Premiere Pro 2025", "/Applications/Adobe Premiere Pro 2026"},
		sections = {
			{id = "editing", title = "Libraries, caches & proxies", detail = "Render caches and proxy media grow with every project. Clear them from the app once a project is finished.", groups = {"video-production"}},
			{id = "adobe", title = "Adobe media caches", detail = "Shared by Premiere Pro and After Effects. Clear them in each app's Media Cache and Disk Cache settings.", items = {"adobe-media-cache", "adobe-caches"}},
		}},
	{id = "photography",
		noun = "photography storage", summary = "across catalogs, previews and raw caches",
		empty = "Lightroom, Capture One and Camera Raw data appear here once measured.",
		footnote = "Previews and raw caches are rebuilt from your photos. Catalogs and sessions are your work: Diskmap never removes them. The Photos library is measured under Photos.",
		markers = {"/Applications/Adobe Lightroom Classic", "~/Pictures/Lightroom", "~/Pictures/Capture One"},
		sections = {
			{id = "catalogs", title = "Catalogs, previews & caches", detail = "Previews and the Camera Raw cache can be rebuilt; catalog backups accumulate until you remove old ones.", groups = {"photography"}},
		}},
	{id = "design",
		noun = "design storage", summary = "across design apps, shared libraries and fonts",
		empty = "Adobe, Figma, Sketch and Affinity data and installed fonts appear here once measured.",
		footnote = "App data can include unsaved work and libraries. Remove apps with their own uninstaller and fonts in Font Book.",
		markers = {"/Applications/Figma.app", "/Applications/Sketch.app", "/Applications/Adobe Creative Cloud", "~/Creative Cloud Files"},
		-- Fonts alone are on every Mac; they do not make someone a designer.
		visibleBytes = 2e9,
		sections = {
			{id = "apps", title = "Design apps & fonts", detail = "Settings, libraries and working files of design tools. Caches are listed separately and can be cleared in each app.", groups = {"design"}},
			{id = "adobe", title = "Adobe caches", detail = "Caches of every Adobe app. Clear them from each app's settings.", items = {"adobe-caches", "camera-raw-cache"}},
		}},
	{id = "studio3d",
		noun = "3D and game engine storage", summary = "across engines, editors and asset caches",
		empty = "Unity, Unreal Engine, Godot and Blender data appear here once measured.",
		footnote = "Engine versions are removed from their launcher. Asset caches rebuild when a project opens, which can take a long time.",
		markers = {"/Applications/Unity Hub.app", "/Applications/Epic Games Launcher.app", "/Applications/Blender.app", "/Applications/Godot.app"},
		sections = {
			{id = "engines", title = "Engines, editors & caches", detail = "Each engine version is several gigabytes. Keep the versions your projects use.", groups = {"studio-3d"}},
		}},
	{id = "games",
		noun = "game storage", summary = "across installed games and launchers",
		empty = "Steam, Epic Games, GOG, Minecraft and Windows game bottles appear here once measured.",
		footnote = "Games download again from their store. Uninstall them from the launcher that installed them, which keeps saves and its library consistent.",
		markers = {"/Applications/Steam.app", "/Applications/Epic Games Launcher.app", "/Applications/Heroic.app"},
		sections = {
			{id = "installed", title = "Installed games & launchers", detail = "The largest games come first. Saved games kept only on this Mac are lost when a game's folder is removed by hand.", groups = {"games"}, items = {"epic-games"}},
		}},
}

return Workflows
