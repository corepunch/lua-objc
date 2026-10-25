_G.__headless = true
local t = require("TestKit")
local xml = require("ui.xml")
local catalog = require("apps.adventure-arena.catalog.Adventures")

local originals = 0
for _, book in ipairs(catalog) do
	if book.collection == "Arena Originals" then originals = originals + 1 end
	t.assertEqual(book.rating, 0, "no unsourced aggregate: " .. book.id)
	t.assertEqual(book.reviewCount, 0, "no unsourced reader count: " .. book.id)
	t.assertEqual(next(book.reviews), nil, "no unsourced review text: " .. book.id)
	t.expect(book.reviewCount >= #book.reviews, "count covers displayed reviews: " .. book.id)
end
t.assertEqual(originals, 6, "all six Arena Originals are audited")

local function render(path, game)
	return xml.describeFile("apps/adventure-arena/views/" .. path .. ".etlua",
		{ game = game, index = 1, id = "book", action = "open", related = {} }).source
end
for _, path in ipairs({ "components/FeaturedCard", "components/GameRow", "pages/Detail" }) do
	for _, book in ipairs(catalog) do
		local source = render(path, book)
		t.expect(source:find("No ratings yet", 1, true), path .. " explains unreviewed state: " .. book.id)
		t.expect(not source:find('name="star', 1, true) and not source:find('systemImage="star', 1, true),
			path .. " does not present zero as a star score")
		t.expect(not source:find("Rated 0.0", 1, true) and not source:find('id="review_', 1, true),
			path .. " has no zero-rating announcement or review cards")
	end
	-- Synthetic feedback is test-only. Keep the genuine-feedback rendering path.
	local rated = {}
	for key, value in pairs(catalog[1]) do rated[key] = value end
	rated.rating, rated.reviewCount = 4.5, 1
	rated.reviews = {{ author = "Test reader", rating = 4, title = "Test title", body = "Test feedback" }}
	local source = render(path, rated)
	t.expect(not source:find("No ratings yet", 1, true), path .. " retains rated state")
	t.expect(source:find("4.5", 1, true), path .. " retains supplied aggregate")
	if path == "pages/Detail" then
		t.expect(source:find("Test feedback", 1, true), "supplied reader text remains visible")
	end
end
os.exit(t.summary() and 0 or 1)
