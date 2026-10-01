_G.__headless = true

local t = require("TestKit")
local Adventures = require("apps.adventure-arena.models.Adventures")
local catalog = Adventures.new()
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local originalOpen, originalPath, originalZilPath = io.open, package.path, package.zilpath
local reads = 0
local function readFile(path)
	reads = reads + 1
	local file, err = originalOpen(path, "r")
	if not file then return nil, err end
	local body = file:read("*a")
	file:close()
	return body
end

local ok, session = pcall(function() return ZILRuntime.new(catalog:find("books.wondertown"), readFile) end)
t.expect(ok, "ZIL runtime loads the bundled Zork source")
t.expect(reads > 0, "runtime uses the injected file reader without a UI platform")
if ok then
	local started, engine, opening = pcall(function()
		return session:start()
	end)
	t.expect(started, "ZIL runtime starts a game coroutine")
	if started then
		t.expect(tostring(opening):find("workshop", 1, true) ~= nil,
			"Wondertown opening text reaches the Lua UI")
		local progress = engine:progress()
		t.assertEqual(progress.score, 0, "runtime reports the game's starting score")
		t.assertEqual(progress.moves, 0, "runtime reports the game's starting move count")
		t.expect(type(progress.maxScore) == "number" and progress.maxScore >= progress.score,
			"runtime reports the game's maximum score")
		local roomName = engine:roomName()
		t.assertEqual(engine:roomIcon(), nil, "a story without room JPGs renders ordinary prose")
		t.expect(type(roomName) == "string" and roomName:lower():find("workshop", 1, true) ~= nil,
			"runtime reports the current room name: " .. tostring(roomName))
		local exits = engine:exits()
		t.expect(type(exits) == "table" and #exits > 0,
			"runtime exposes current room exits for the compass")
		local resumed, response = pcall(function() return engine:resume("look") end)
		t.expect(resumed and type(response) == "string", "typed commands reach the runtime")
		t.expect(engine:progress().moves > 0, "runtime progress advances after a typed command")
	end
end

local horror = catalog:find("books.blackwood-horror")
local gateImage = "apps/adventure-arena/assets/books/blackwood-horror/images/SANITARIUM-GATE.jpg"
local entranceImage = "apps/adventure-arena/assets/books/blackwood-horror/images/SANITARIUM-ENTRANCE.jpg"
local hiddenImage = false
local function artworkReader(path)
	if hiddenImage and path:match("%.jpg$") then return nil, "missing fixture image" end
	return readFile(path)
end
local horrorEngine = ZILRuntime.new(horror, artworkReader, 42):start()
t.assertEqual(horrorEngine:roomIcon(), gateImage, "streamed reader finds the ROOM-named JPG without an ICON field")
local before = horrorEngine:progress().moves
hiddenImage = true
t.assertEqual(horrorEngine:roomIcon(), nil, "missing artwork leaves a room without a figure")
hiddenImage = false
t.assertEqual(horrorEngine:roomIcon(), gateImage, "artwork can appear without restarting the session")
t.assertEqual(horrorEngine:progress().moves, before, "artwork lookup does not advance the game")
horrorEngine:resume("north")
t.assertEqual(horrorEngine:roomIcon(), entranceImage, "navigation selects the new ROOM identifier rather than its display title")
horrorEngine:resume("south")
t.assertEqual(horrorEngine:roomIcon(), gateImage, "returning to a room restores its image")
local diskEngine = ZILRuntime.new(horror, nil, 42):start()
t.assertEqual(diskEngine:roomIcon(), gateImage, "local disk uses the same artwork convention as streaming")
local roomCount = 0
local dungeon = readFile("apps/adventure-arena/zilscript/books/blackwood-horror/dungeon.zil")
for room in dungeon:gmatch("<ROOM%s+([%w_-]+)") do
	roomCount = roomCount + 1
	local jpg = readFile("apps/adventure-arena/assets/books/blackwood-horror/images/" .. room .. ".jpg")
	t.expect(jpg and jpg:sub(1, 2) == "\255\216", room .. " has a matching JPEG illustration")
end
t.assertEqual(roomCount, 22, "the artwork covers all 22 horror rooms")

t.assertEqual(io.open, originalOpen, "runtime restores host file IO")
t.assertEqual(package.path, originalPath, "runtime restores Lua import paths")
t.assertEqual(package.zilpath, originalZilPath, "runtime restores ZIL import paths")
t.assertThrows(function()
	ZILRuntime.new(catalog:find("books.wondertown"), function() error("fixture read failure") end)
end, "stream read failures propagate")
t.assertEqual(io.open, originalOpen, "failed streamed load restores file IO")
t.assertEqual(package.path, originalPath, "failed streamed load restores Lua paths")
t.assertEqual(package.zilpath, originalZilPath, "failed streamed load restores ZIL paths")

os.exit(t.summary() and 0 or 1)
