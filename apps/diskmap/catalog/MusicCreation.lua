-- Music production: Apple's music apps with their sound libraries, sample
-- libraries and instruments from other makers, and audio plug-ins. Paths are
-- each product's default location; a library moved to another folder or disk
-- is not measured here. The Music Production page (knowledge/Workflows.lua)
-- presents these groups.
local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
local library = {nature = "library", remover = "owner", threshold = 10e9}
local function owned(owner, options)
	return D.with(options or library, {advice = "Remove content you no longer use from " .. owner .. ", which keeps its library consistent. Removed content can be downloaded or installed again."})
end
return function()
	return group("music-creation", "Music Creation", "GarageBand, Logic, sample libraries and audio plug-ins", "pianokeys", "systemPink", {
		group("apple-music-apps", "GarageBand & Logic", "Projects and the sound libraries Apple's music apps download", "pianokeys", "systemPink", {
			item("garageband", "GarageBand projects", "GarageBand projects and recordings", "~/Music/GarageBand", {nature = "personal"}),
			item("logic", "Logic Pro projects", "Logic projects, bounces and their audio files", "~/Music/Logic", {nature = "personal"}),
			item("audio-music-apps", "Patches, presets & user loops", "Content shared by GarageBand, Logic and MainStage", "~/Music/Audio Music Apps"),
			item("logic-sound-library", "Logic sound library", "Instruments, samples and drum kits downloaded by Logic Pro and MainStage", "/Library/Application Support/Logic",
				owned("Logic Pro › Sound Library › Open Sound Library Manager")),
			item("garageband-sound-library", "GarageBand sound library", "Instruments and lessons downloaded by GarageBand", "/Library/Application Support/GarageBand",
				owned("GarageBand › Sound Library")),
			item("apple-loops", "Apple Loops", "Loops installed for GarageBand, Logic and Final Cut Pro", "/Library/Audio/Apple Loops",
				owned("the app that installed them")),
		}),
		group("sample-libraries", "Instruments & sample libraries", "Sample content installed by other music software", "waveform", "systemPink", {
			item("ableton", "Ableton Live", "User Library, Packs and Live projects", "~/Music/Ableton", owned("Ableton Live's browser")),
			item("ableton-cache", "Ableton Live cache", "Decoded audio and analysis files; Live creates them again", "~/Library/Caches/Ableton",
				{nature = "cache", remover = "finder", threshold = 2e9, advice = "Quit Live before removing anything here. Live analyses and decodes audio again the next time a set uses it."}),
			item("native-instruments", "Native Instruments content", "User content for Kontakt, Maschine and other instruments", "~/Documents/Native Instruments", owned("Native Access")),
			item("native-instruments-shared", "Native Instruments shared data", "Shared presets, databases and Service Center data", "/Library/Application Support/Native Instruments", owned("Native Access")),
			item("spectrasonics", "Spectrasonics STEAM library", "Omnisphere, Keyscape and Trilian sound sources", "~/Library/Application Support/Spectrasonics",
				{nature = "library", remover = "owner", threshold = 10e9, advice = "The sound sources Omnisphere, Keyscape and Trilian play. The instruments cannot work without them; move the STEAM folder to another disk with Spectrasonics' instructions instead of deleting it."}),
			item("arturia", "Arturia instruments", "Presets and resources for V Collection and Pigments", "/Library/Arturia", owned("Arturia Software Center")),
			item("splice", "Splice sounds", "Samples and presets downloaded from Splice", "~/Splice", owned("the Splice app")),
			item("image-line", "FL Studio", "Projects, recordings and downloaded content", "~/Documents/Image-Line", {nature = "personal"}),
			item("pro-tools", "Pro Tools sessions", "Sessions and their audio files", "~/Documents/Pro Tools", {nature = "personal"}),
		}),
		group("audio-plugins", "Audio plug-ins & shared audio", "Audio Units, VST and AAX plug-ins with their presets", "slider.horizontal.3", "systemPink", {
			item("audio-plugins-shared", "Plug-ins for all users", "Audio Units, VST, VST3 and AAX plug-ins", "/Library/Audio/Plug-Ins",
				{remover = "owner", advice = "Remove a plug-in with its maker's uninstaller. Projects that use it open without its sound or effect."}),
			item("audio-plugins-user", "Your plug-ins", "Plug-ins installed for your account only", "~/Library/Audio/Plug-Ins",
				{remover = "owner", advice = "Remove a plug-in with its maker's uninstaller. Projects that use it open without its sound or effect."}),
			item("audio-shared", "Other shared audio content", "Impulse responses, presets and MIDI drivers", "/Library/Audio"),
			item("audio-user", "Your presets & audio settings", "Plug-in presets, channel strip settings and sounds", "~/Library/Audio"),
		}),
	})
end
