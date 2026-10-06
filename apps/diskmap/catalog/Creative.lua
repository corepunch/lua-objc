-- Video, photography, design and 3D work: the project libraries, caches and
-- app data creative tools keep outside their documents. Paths are each
-- product's default location; media kept on another disk or in a custom
-- folder is not measured here. One group per page in knowledge/Workflows.lua.
local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
-- Render files and proxies are recreated from the source media, but only
-- while that media is still connected: never offered as a plain cache.
local function render(owner)
	return {nature = "cache", remover = "owner", threshold = 5e9, advice = "Delete it from " .. owner .. ". The app creates it again from your source media, which must still be available; playback and export are slower until it has."}
end
local function appData(owner)
	return {remover = "owner", advice = "Settings, databases and working files of " .. owner .. ". Manage them in the app; removing the folder resets it."}
end
return function()
	return group("creative", "Creative Apps", "Video, photography, design and 3D work outside your documents", "paintpalette.fill", "systemPink", {
		group("video-production", "Video production", "Editing libraries, render caches and proxies", "film.fill", "systemPurple", {
			item("imovie-library", "iMovie library", "Events, projects and imported media", "~/Movies/iMovie Library.imovielibrary",
				{nature = "personal", remover = "owner", threshold = 10e9, advice = "Delete finished projects and unused events in iMovie, or move the library to another disk with the Finder while iMovie is closed."}),
			item("imovie-theater", "iMovie Theater", "Finished movies shared to the Theater", "~/Movies/iMovie Theater.theater", {nature = "personal", remover = "owner"}),
			item("final-cut-backups", "Final Cut Pro library backups", "Automatic copies of each library's database, without media", "~/Movies/Final Cut Backups",
				{nature = "appData", remover = "finder", threshold = 2e9, advice = "Backups of library databases, kept per library. Old ones can be removed in the Finder; choose where they go in Final Cut Pro › Library Properties."}),
			item("motion-templates", "Motion templates", "Titles, effects, transitions and generators for Final Cut Pro and Motion", "~/Movies/Motion Templates.localized"),
			item("resolve-cache", "DaVinci Resolve render cache", "Cached frames for playback at the default cache location", "~/Movies/CacheClip",
				render("Playback › Delete Render Cache in DaVinci Resolve")),
			item("resolve-proxies", "DaVinci Resolve proxy media", "Proxy and optimized media at the default location", "~/Movies/ProxyMedia",
				render("the Media Pool in DaVinci Resolve")),
			item("resolve-data", "DaVinci Resolve projects & settings", "The project database, LUTs and settings for your account", "~/Library/Application Support/Blackmagic Design", appData("DaVinci Resolve")),
			item("resolve-shared", "DaVinci Resolve shared data", "Shared project databases, LUTs and Fusion templates", "/Library/Application Support/Blackmagic Design", appData("DaVinci Resolve")),
			item("adobe-documents", "Adobe projects & auto-saves", "Premiere Pro and After Effects projects, auto-saves and previews", "~/Documents/Adobe",
				{nature = "personal", remover = "finder", threshold = 5e9, advice = "Auto-save copies and preview files accumulate per project. Review old versions in the Finder; keep the projects you still work on."}),
			item("adobe-media-cache-database", "Adobe media cache database", "The index of Premiere Pro and After Effects cache files", "~/Library/Application Support/Adobe/Common/Media Cache",
				render("Premiere Pro › Settings › Media Cache")),
			item("obs", "OBS Studio", "Scenes, profiles, plug-ins and logs", "~/Library/Application Support/obs-studio", appData("OBS Studio")),
		}),
		group("photography", "Photography", "Photo catalogs, previews and raw caches outside the Photos library", "camera.fill", "systemOrange", {
			item("lightroom-classic", "Lightroom Classic catalogs", "Catalogs with their previews and backups", "~/Pictures/Lightroom",
				{nature = "personal", remover = "owner", threshold = 5e9, advice = "Previews are rebuilt from your photos; catalog backups accumulate one per backup. Remove old backups in the Finder and purge previews from Lightroom Classic's catalog settings. Never delete the .lrcat catalog itself."}),
			item("lightroom-library", "Lightroom library", "Originals and smart previews Lightroom keeps on this Mac", "~/Pictures/Lightroom Library.lrlibrary",
				{nature = "personal", remover = "owner", threshold = 5e9, advice = "Lightroom's local copies of cloud photos. Reduce them in Lightroom › Settings › Local Storage; photos not yet synced exist only here."}),
			item("camera-raw-cache", "Camera Raw cache", "Rendered raw previews shared by Lightroom Classic, Photoshop and Bridge", "~/Library/Caches/Adobe Camera Raw",
				{nature = "cache", remover = "owner", threshold = 2e9, advice = "Purge it from Camera Raw's Performance settings in Lightroom Classic, Photoshop or Bridge, where its size limit is set too. Previews of raw files are rendered again as you open them."}),
			item("camera-raw-settings", "Camera Raw profiles & presets", "Camera and lens profiles, presets and settings", "~/Library/Application Support/Adobe/CameraRaw"),
			item("capture-one", "Capture One", "Catalogs and sessions at the default location", "~/Pictures/Capture One",
				{nature = "personal", remover = "owner", threshold = 5e9, advice = "Catalogs and sessions with their previews and, for sessions, the photos themselves. Review them in Capture One."}),
			item("capture-one-data", "Capture One app data", "Styles, presets, ICC profiles and batch queue", "~/Library/Application Support/Capture One", appData("Capture One")),
		}),
		group("design", "Design", "Design tools, shared libraries and fonts", "paintbrush.pointed.fill", "systemTeal", {
			item("creative-cloud-files", "Creative Cloud Files", "Files synced with your Creative Cloud storage", "~/Creative Cloud Files", {nature = "personal", remover = "owner"}),
			item("adobe-support", "Adobe app data", "Settings, presets, libraries and working files of Adobe apps", "~/Library/Application Support/Adobe", appData("each Adobe app")),
			item("adobe-shared", "Adobe shared components", "Components, installers and content shared by Adobe apps", "/Library/Application Support/Adobe",
				{remover = "owner", advice = "Shared by every installed Adobe app. Remove Adobe apps with Creative Cloud, which cleans up what they shared."}),
			item("figma", "Figma", "The desktop app's cached files and settings", "~/Library/Application Support/Figma", appData("Figma")),
			item("sketch", "Sketch", "Libraries, plug-ins and settings", "~/Library/Application Support/com.bohemiancoding.sketch3", appData("Sketch")),
			item("sketch-cache", "Sketch cache", "Previews and downloaded library updates", "~/Library/Caches/com.bohemiancoding.sketch3",
				{nature = "cache", remover = "finder", threshold = 1e9, advice = "Quit Sketch before removing anything here. Sketch downloads library updates and draws previews again."}),
			item("affinity", "Affinity", "Documents' working data, assets and settings of Affinity apps", "~/Library/Application Support/Affinity", appData("Affinity")),
			item("pixelmator-pro", "Pixelmator Pro", "Working data, presets and settings", "~/Library/Containers/com.pixelmatorteam.pixelmator.x", appData("Pixelmator Pro")),
			item("fonts-user", "Your fonts", "Fonts installed for your account", "~/Library/Fonts",
				{remover = "owner", advice = "Remove fonts in Font Book. Documents that use a removed font substitute another."}),
			item("fonts-shared", "Fonts for all users", "Fonts installed for every account on this Mac", "/Library/Fonts",
				{remover = "owner", advice = "Remove fonts in Font Book. Documents that use a removed font substitute another."}),
		}),
		group("studio-3d", "3D & game engines", "3D tools, game engines and their asset caches", "cube.fill", "systemIndigo", {
			item("unity-editors", "Unity editors", "Each Unity version installed by Unity Hub, with its platform modules", "/Applications/Unity/Hub/Editor",
				{nature = "library", remover = "owner", threshold = 10e9, advice = "Remove editor versions no project uses from Unity Hub › Installs. A project opened later asks for its version again."}),
			item("unity-cache", "Unity caches & Asset Store downloads", "Package caches and downloaded Asset Store packages", "~/Library/Unity",
				{nature = "cache", remover = "owner", threshold = 5e9, advice = "Packages download again when a project needs them. Asset Store downloads can be fetched again from your account."}),
			item("epic-games", "Epic Games installs", "Unreal Engine versions and games installed by the Epic Games Launcher", "/Users/Shared/Epic Games",
				{nature = "library", remover = "owner", threshold = 20e9, advice = "Uninstall engine versions and games from the Epic Games Launcher's library, which keeps its records consistent."}),
			item("unreal-data", "Unreal Engine data", "Derived data cache, launcher data and settings", "~/Library/Application Support/Epic",
				{nature = "cache", remover = "owner", threshold = 5e9, advice = "The derived data cache is rebuilt when a project opens, which can take a long time. Clear it from Unreal Editor's Derived Data menu."}),
			item("blender", "Blender", "Add-ons, settings and caches for each Blender version", "~/Library/Application Support/Blender", appData("Blender")),
			item("godot", "Godot", "Editor data and export templates", "~/Library/Application Support/Godot",
				{remover = "owner", advice = "Export templates download again from Godot's export dialog. Editor settings are kept here too."}),
			item("godot-cache", "Godot cache", "Shader and editor caches", "~/Library/Caches/Godot",
				{nature = "cache", remover = "finder", threshold = 1e9, advice = "Quit Godot before removing anything here. Shaders compile again the next time a project runs."}),
		}),
	})
end
