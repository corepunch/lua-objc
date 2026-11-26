-- The German library: the German editions only. An edition is its own book
-- with its own id (the engine keeps it in the book's `de` folder), so its
-- saves never mix with the English one's. Every entry is shown only when the
-- app speaks German (Store.lua).
return {
	{
		id = "books.blackout-at-meridian.de",
		collection = "Arena-Originale",
		difficulty = "Standard",
		statusLine = "moves",
		title = "Stromausfall in Meridian",
		shortDescription = "Erschaffe einen Helden und rette eine Stadt im Dunkeln.",
		description = "Gib deinem Helden einen Namen und wähle eines von drei Superhelden-Profilen: Fels, Blitz oder Luchs. Rette die Fahrgäste einer festgefahrenen Straßenbahn und bring das Stromrelais der Stadt zurück, mit Würfelproben, Heldenwerten und kluger Einteilung deiner Kräfte. Ein Rollenspiel-Abenteuer nach Art der Tischrollenspiele, auf Deutsch.",
		author = "AdventureArena",
		year = 2026,
		rating = 0,
		reviewCount = 0,
		startFile = "blackout-at-meridian.zil",
		ruleset = "superhero-percentile",
		reviews = {},
		genre = "Superhelden-Rollenspiel",
		categories = { "Superhelden" },
		cover = "apps/adventure-arena/assets/blackout-at-meridian.png",
	},
}
