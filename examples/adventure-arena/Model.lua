local Model = {}

-- Catalog metadata mirrors AdventureArena's game.json contract. Keeping this
-- table pure makes the catalog useful in headless tests and on the simulator
-- before a remote content store exists.
Model.games = {
	{
		id = "infocom.zork1",
		title = "Zork I: The Great Underground Empire",
		shortDescription = "Explore the Great Underground Empire.",
		description = "You are standing in an open field west of a white house, with a boarded front door.",
		genre = "Classic Adventure",
		author = "Infocom",
		year = 1980,
		rating = 4.8,
		reviewCount = 2341,
		systemImage = "map",
	},
	{
		id = "infocom.planetfall",
		title = "Planetfall",
		shortDescription = "Survive a crash landing on an alien world.",
		description = "Your ship has been destroyed. Explore the ruins of a lost civilization and unravel its mystery.",
		genre = "Sci-Fi Adventure",
		author = "Infocom",
		year = 1983,
		rating = 4.7,
		reviewCount = 2104,
		systemImage = "globe",
	},
	{
		id = "infocom.lurkinghorror",
		title = "The Lurking Horror",
		shortDescription = "Something ancient stirs beneath the campus.",
		description = "A blizzard rages outside G.U.E. Tech. You descend into steam tunnels where something malevolent stirs.",
		genre = "Psychological Horror",
		author = "Infocom",
		year = 1987,
		rating = 4.3,
		reviewCount = 723,
		systemImage = "moon.stars",
	},
}

local gameIndex = {}
for _, game in ipairs(Model.games) do
	gameIndex[game.id] = game
end

function Model.game(id)
	return gameIndex[id]
end

function Model.featured()
	local result = {}
	for i = 1, math.min(3, #Model.games) do
		result[#result + 1] = Model.games[i]
	end
	return result
end

function Model.ratingLabel(game)
	return string.format("%.1f (%d)", game.rating, game.reviewCount)
end

return Model
