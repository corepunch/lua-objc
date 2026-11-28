local t = require("TestKit")
local Suggestions = require("apps.adventure-arena.zilscript.zilscript.reader.Suggestions")

local key = { target = "brass key", noun = "key", aliases = { "key", "passkey" } }
local door = { target = "oak door", noun = "door", aliases = { "door" } }
local function complete(input, items)
	return Suggestions.forInput(input, items, function(offer)
		offer("unlock", door, "with", key)
		offer("put", key, "in", door)
	end)
end
local function has(input, items, title, text)
	for _, choice in ipairs(complete(input, items)) do
		if choice.title == title and choice.text == text then return true end
	end
	return false
end

t.expect(has("put passkey ", { key, door }, "in", "put passkey in "),
	"an object's parser synonym continues to the preposition")
t.expect(has("put passkey in ", { key, door }, "door", "put passkey in door "),
	"a synonym preserves the typed command while completing its second object")
t.expect(has("unlock door with ", { key, door }, "key", "unlock door with key "),
	"a normal noun still reaches the second object")
local other = { target = "iron key", noun = "key", aliases = { "key", "passkey" } }
t.expect(not has("put passkey ", { key, door, other }, "in", "put passkey in "),
	"an ambiguous synonym does not advance as if it identified one object")
os.exit(t.summary() and 0 or 1)
