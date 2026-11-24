local Model = require("data.model")

-- The catalog of adventures, the store's `adventures` table in editorial
-- order: shelves, charts, genres and search are queries over it.
local Adventures = Model:extend("adventures")

-- Shelves stay browsable at 20-30 titles: a carousel longer than this is a
-- list nobody finishes, so the shelf heading opens the full collection.
local LIBRARY = { featured = 3, shelf = 10, chart = 5, related = 6 }

-- Symbols for the onboarding genre choices.
local GENRE_SYMBOLS = {
	["Children's Adventure"] = "cloud.sun.fill",
	["Science Fiction Horror"] = "waveform",
	["Science Fiction"] = "sparkles",
	["Supernatural Suspense"] = "eye.fill",
	["Historical Detective Mystery"] = "magnifyingglass",
	["Sci-Fi Adventure"] = "sparkles",
	["Psychological Horror"] = "eye.fill",
	["Fantasy Adventure"] = "wand.and.stars",
	["Whimsical Adventure"] = "gearshape.2.fill",
	["Victorian Mystery"] = "magnifyingglass",
	["Classic Adventure"] = "map.fill",
}

function Adventures.genreSymbol(genre)
	return GENRE_SYMBOLS[genre] or "book.fill"
end

function Adventures:featured()
	return self:select(nil, {limit = LIBRARY.featured})
end

local function collectionOf(game)
	return game.collection or game.genre or "Adventures"
end

local function groupShelves(games, titleOf)
	local shelves, byTitle = {}, {}
	for _, game in ipairs(games) do
		local title = titleOf(game)
		if title then
			local shelf = byTitle[title]
			if not shelf then
				shelf = { id = title, title = title, games = {}, count = 0 }
				byTitle[title] = shelf
				table.insert(shelves, shelf)
			end
			shelf.count = shelf.count + 1
			if #shelf.games < LIBRARY.shelf then table.insert(shelf.games, game) end
		end
	end
	return shelves
end

-- Shelves follow their first appearance in the catalog.
function Adventures:shelves()
	return groupShelves(self:all(), collectionOf)
end

function Adventures:genreShelves()
	return groupShelves(self:all(), function(game) return game.category end)
end

function Adventures:collection(title)
	return self:select(function(game) return collectionOf(game) == title or game.category == title end)
end

-- Genres inform the onboarding recommendations.
function Adventures:genres()
	local genres, seen = {}, {}
	for _, game in ipairs(self:all()) do
		if game.genre and not seen[game.genre] then
			seen[game.genre] = true
			table.insert(genres, { id = game.genre, title = game.genre,
				symbol = Adventures.genreSymbol(game.genre), count = self:count({ genre = game.genre }) })
		end
	end
	return genres
end

function Adventures:topRated(limit)
	local ranked = self:all()
	table.sort(ranked, function(a, b)
		if (a.rating or 0) ~= (b.rating or 0) then return (a.rating or 0) > (b.rating or 0) end
		if (a.reviewCount or 0) ~= (b.reviewCount or 0) then return (a.reviewCount or 0) > (b.reviewCount or 0) end
		return a.title < b.title
	end)
	local top = {}
	for index = 1, math.min(limit or LIBRARY.chart, #ranked) do
		table.insert(top, { rank = index, game = ranked[index] })
	end
	return top
end

function Adventures:related(id, limit)
	local game = self:find(id)
	if not game then return {} end
	local related = {}
	limit = limit or LIBRARY.related
	local function add(candidate)
		if #related >= limit or candidate.id == id then return end
		for _, existing in ipairs(related) do
			if existing.id == candidate.id then return end
		end
		table.insert(related, candidate)
	end
	for _, candidate in ipairs(self:all()) do
		if collectionOf(candidate) == collectionOf(game) then add(candidate) end
	end
	for _, candidate in ipairs(self:all()) do
		if candidate.genre == game.genre then add(candidate) end
	end
	return related
end

local function searchable(game)
	return table.concat({
		game.title or "", game.author or "", game.genre or "", collectionOf(game), game.category or "",
		game.shortDescription or "", tostring(game.year or ""), game.difficulty or "",
	}, " "):lower()
end

-- Every query word must match somewhere, so "zork wizard" narrows instead of
-- widening. Title matches rank first; ties keep catalog order.
function Adventures:search(query)
	local terms = {}
	for term in tostring(query or ""):lower():gmatch("%S+") do table.insert(terms, term) end
	if #terms == 0 then return {} end
	local matches = {}
	for index, game in ipairs(self:all()) do
		local text, title, matched = searchable(game), (game.title or ""):lower(), true
		local titleHits = 0
		for _, term in ipairs(terms) do
			if not text:find(term, 1, true) then matched = false break end
			if title:find(term, 1, true) then titleHits = titleHits + 1 end
		end
		if matched then table.insert(matches, { game = game, titleHits = titleHits, index = index }) end
	end
	table.sort(matches, function(a, b)
		if a.titleHits ~= b.titleHits then return a.titleHits > b.titleHits end
		return a.index < b.index
	end)
	local games = {}
	for _, match in ipairs(matches) do table.insert(games, match.game) end
	return games
end

return Adventures
