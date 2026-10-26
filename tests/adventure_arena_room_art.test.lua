_G.__headless = true
local t = require("TestKit")
local Runtime = require("apps.adventure-arena.services.ZILRuntime")
local catalog = require("apps.adventure-arena.catalog.Adventures")
local rooms, books = 0, 0
local originalOpen = io.open
for _, book in ipairs(catalog) do
	if book.id:match("^books%.") then
		books = books + 1
		local source = book.id:gsub("%.", "/")
		local file = assert(io.open("apps/adventure-arena/zilscript/" .. source .. "/dungeon.zil"))
		local text = file:read("*a"); file:close()
		for room in text:gmatch("<ROOM%s+([%w-]+)") do
			rooms = rooms + 1
			local image = io.open("apps/adventure-arena/assets/" .. source .. "/images/" .. room .. ".jpg", "rb")
			t.expect(image ~= nil, book.id .. ": artwork exists for " .. room)
			if image then
				t.assertEqual(image:read(3), "\255\216\255", "room image is a JPEG")
				image:close()
			end
		end
		for _, streamed in ipairs({false, true}) do
			local readFile = streamed and function(path)
				local input = originalOpen(path, "rb")
				if not input then return nil end
				local contents = input:read("*a"); input:close(); return contents
			end or nil
			local engine = Runtime.new(book, readFile, 42):start()
			t.expect(engine:roomIcon() ~= nil, book.id .. ": opening artwork discovered locally and streamed")
			local before = engine:progress().moves
			engine:roomIcon()
			t.assertEqual(engine:progress().moves, before, "artwork discovery does not advance story")
		end
	end
end
t.assertEqual(books, 6, "every original book is illustrated")
t.assertEqual(rooms, 85, "every authored room is covered")
os.exit(t.summary() and 0 or 1)
