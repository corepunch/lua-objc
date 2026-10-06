-- Games and the launchers that install them. Games are large and download
-- again from their store, so each store's own library is where to remove
-- them. The Games page (knowledge/Workflows.lua) presents this group.
local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
local function store(name, saves)
	return {nature = "library", remover = "owner", threshold = 10e9, advice = "Uninstall games you no longer play from " .. name .. ". Games download again from the store" .. (saves and ("; " .. saves) or "") .. "."}
end
return function()
	return group("games", "Games", "Installed games and the launchers that manage them", "gamecontroller.fill", "systemGreen", {
		item("steam-games", "Steam games", "Installed games and their downloaded content", "~/Library/Application Support/Steam/steamapps",
			store("Steam's library", "saves in Steam Cloud are kept")),
		item("steam", "Steam client", "The Steam app's data, shader caches and screenshots", "~/Library/Application Support/Steam"),
		item("gog", "GOG Galaxy", "The launcher's data and downloaded installers", "~/Library/Application Support/GOG.com", store("GOG Galaxy")),
		item("battle-net", "Battle.net", "The launcher's data and caches", "~/Library/Application Support/Battle.net"),
		item("minecraft", "Minecraft", "Worlds, resource packs, mods and game versions", "~/Library/Application Support/minecraft",
			{nature = "personal", remover = "owner", threshold = 5e9, advice = "Worlds in the saves folder are your own and exist only here unless you back them up. Old game versions download again from the launcher."}),
		item("crossover", "CrossOver bottles", "Windows apps and games installed with CrossOver", "~/Library/Application Support/CrossOver",
			{nature = "personal", remover = "owner", threshold = 10e9, advice = "Each bottle holds a Windows installation with its apps and saved games. Delete bottles you no longer use in CrossOver."}),
		item("whisky", "Whisky bottles", "Windows games installed with Whisky", "~/Library/Containers/com.isaacmarovitz.Whisky",
			{nature = "personal", remover = "owner", threshold = 10e9, advice = "Each bottle holds a Windows installation with its games and saves. Delete bottles you no longer use in Whisky."}),
		item("heroic", "Heroic Games Launcher", "Launcher data, Wine versions and prefixes", "~/Library/Application Support/heroic",
			{nature = "appData", remover = "owner", threshold = 5e9, advice = "Remove unused Wine versions and games from Heroic's settings and library."}),
		item("heroic-games", "Heroic games", "Games Heroic installed at its default location", "~/Games/Heroic", store("Heroic's library")),
		item("prism-launcher", "Prism Launcher", "Minecraft instances with their worlds, mods and game versions", "~/Library/Application Support/PrismLauncher",
			{nature = "personal", remover = "owner", threshold = 5e9, advice = "Each instance holds its own worlds and mods. Delete instances you no longer play in Prism Launcher; game versions download again."}),
		item("roblox", "Roblox", "The Roblox player, Studio and their downloads", "~/Library/Roblox",
			{nature = "cache", remover = "owner", threshold = 2e9, advice = "Roblox downloads what it needs again. Experiences are saved online, not here."}),
		item("openemu", "OpenEmu", "Your game library, save states and screenshots", "~/Library/Application Support/OpenEmu",
			{nature = "personal", remover = "owner", threshold = 5e9, advice = "Remove games in OpenEmu's library. Save states exist only here unless you back them up."}),
	})
end
