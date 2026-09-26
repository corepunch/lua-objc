local Adventures = {}
Adventures.__index = Adventures

-- Shelves stay browsable at 20-30 titles: a carousel longer than this is a
-- list nobody finishes, so the rest lives behind the shelf's "See All".
local LIBRARY = { featured = 3, shelf = 10, chart = 5, related = 6 }

function Adventures.new(options)
	options = options or {}
	local games = options.games or require("apps.adventure-arena.catalog.Adventures")
	local gamesById = {}
	for _, game in ipairs(games) do gamesById[game.id] = game end
	return setmetatable({ games = games, gamesById = gamesById }, Adventures)
end

function Adventures:list()
	local games = {}
	for _, game in ipairs(self.games) do table.insert(games, game) end
	return games
end

function Adventures:find(id)
	return self.gamesById[id]
end

function Adventures:featured()
	local games = {}
	for index = 1, math.min(LIBRARY.featured, #self.games) do table.insert(games, self.games[index]) end
	return games
end

local function collectionOf(game)
	return game.collection or game.genre or "Adventures"
end

-- Shelves follow the catalog's first mention of each collection, so catalog
-- order is the editorial order and needs no second ranking table.
function Adventures:shelves()
	local shelves, byTitle = {}, {}
	for _, game in ipairs(self.games) do
		local title = collectionOf(game)
		local shelf = byTitle[title]
		if not shelf then
			shelf = { id = title, title = title, games = {}, count = 0 }
			byTitle[title] = shelf
			table.insert(shelves, shelf)
		end
		shelf.count = shelf.count + 1
		if #shelf.games < LIBRARY.shelf then table.insert(shelf.games, game) end
	end
	return shelves
end

function Adventures:collection(title)
	local games = {}
	for _, game in ipairs(self.games) do
		if collectionOf(game) == title or game.genre == title then table.insert(games, game) end
	end
	return games
end

-- Genres become the "Browse by Genre" tiles; each tile borrows the tint of
-- its first game so the grid previews the worlds behind it.
function Adventures:genres()
	local genres, seen = {}, {}
	for _, game in ipairs(self.games) do
		if game.genre and not seen[game.genre] then
			seen[game.genre] = true
			table.insert(genres, { id = game.genre, title = game.genre, tint = game.tint, count = #self:collection(game.genre) })
		end
	end
	return genres
end

function Adventures:topRated(limit)
	local ranked = self:list()
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
	for _, candidate in ipairs(self.games) do
		if collectionOf(candidate) == collectionOf(game) then add(candidate) end
	end
	for _, candidate in ipairs(self.games) do
		if candidate.genre == game.genre then add(candidate) end
	end
	return related
end

local function searchable(game)
	return table.concat({
		game.title or "", game.author or "", game.genre or "", collectionOf(game),
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
	for index, game in ipairs(self.games) do
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
