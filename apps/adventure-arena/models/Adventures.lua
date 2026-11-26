local Model = require("data.model")
local Languages = require("apps.adventure-arena.helpers.Languages")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")

-- The catalog of adventures in the app's language (ReadingSettings.language),
-- from the store's `adventures` table in editorial order: shelves, charts,
-- genres and search are queries over it. A game with no `language` is shown
-- in every language; an edition is shown only in its own.
local Adventures = Model:extend("adventures", { source = function(db)
	local language = ReadingSettings.language()
	local games = {}
	for _, game in ipairs(db.adventures or {}) do
		if not game.language or game.language == language then table.insert(games, game) end
	end
	return games
end })

-- Shelves stay browsable at 20-30 titles: a carousel longer than this is a
-- list nobody finishes, so the shelf heading opens the full collection.
local LIBRARY = { shelf = 10, chart = 5, related = 6 }
local DISCOVER_SHELF_ORDER = { "Read with Kids", "Detective", "Horror" }

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
	["Superhero RPG"] = "bolt.fill",
	["Superhelden-Rollenspiel"] = "bolt.fill",
	["Kinderabenteuer"] = "cloud.sun.fill",
	["Science-Fiction"] = "sparkles",
}

function Adventures.genreSymbol(genre)
	return GENRE_SYMBOLS[genre] or "book.fill"
end

local function collectionOf(game)
	return game.collection or game.genre
end

local function groupShelves(games, titlesOf)
	local shelves, byTitle = {}, {}
	for _, game in ipairs(games) do
		for _, title in ipairs(titlesOf(game)) do
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
	return shelves, byTitle
end

-- Shelves follow their first appearance in the catalog.
function Adventures:shelves()
	local shelves = groupShelves(self:all(), function(game) return { collectionOf(game) } end)
	return shelves
end

function Adventures:genreShelves()
	local shelves, byTitle = groupShelves(self:all(), function(game) return game.categories or {} end)
	local ordered = {}
	for _, title in ipairs(DISCOVER_SHELF_ORDER) do
		local shelf = byTitle[title]
		if shelf then
			table.insert(ordered, shelf)
			byTitle[title] = nil
		end
	end
	for _, shelf in ipairs(shelves) do
		if byTitle[shelf.title] then table.insert(ordered, shelf) end
	end
	return ordered
end

function Adventures:collection(title)
	return self:select(function(game)
		if collectionOf(game) == title then return true end
		for _, category in ipairs(game.categories or {}) do
			if category == title then return true end
		end
		return false
	end)
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
	return Languages.lower(table.concat({
		game.title or "", game.author or "", game.genre or "", collectionOf(game), table.concat(game.categories or {}, " "),
		game.shortDescription or "", tostring(game.year or ""), game.difficulty or "",
	}, " "))
end

-- Every query word must match somewhere, so "zork wizard" narrows instead of
-- widening. Title matches rank first; ties keep catalog order.
function Adventures:search(query)
	local terms = {}
	for term in Languages.lower(tostring(query or "")):gmatch("%S+") do table.insert(terms, term) end
	if #terms == 0 then return {} end
	local matches = {}
	for index, game in ipairs(self:all()) do
		local text, title, matched = searchable(game), Languages.lower(game.title or ""), true
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
