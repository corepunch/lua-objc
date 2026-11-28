local t = require("TestKit")
package.path = "apps/adventure-arena/zilscript/?.lua;apps/adventure-arena/zilscript/?/init.lua;" .. package.path
local Story = require("apps.adventure-arena.zilscript.zilscript.reader.Story")
local story = Story.of("books/en/last-door-of-battleworld", "apps/adventure-arena/zilscript")
local function contains(list, value)
	for _, path in ipairs(list) do if path == value then return true end end
	return false
end
for _, part in ipairs({ "en", "early", "village", "late" }) do
	local path = "books/en/last-door-of-battleworld/" .. part .. ".zil"
	t.expect(contains(story.words, path), "vocabulary checks read " .. path)
	t.expect(contains(story.declarations, path), "parser checks read declarations in " .. path)
end
local make = assert(io.popen("make -s -n -C apps/adventure-arena/zilscript lint-zil"))
local commands = make:read("a")
make:close()
local vocabulary = commands:match("lua5%.4 scripts/check%-vocab%.lua ([^\n]+)") or ""
for _, part in ipairs({ "en", "early", "village", "late" }) do
	t.expect(vocabulary:find("books/en/last-door-of-battleworld/" .. part .. ".zil", 1, true) ~= nil,
		"make passes the " .. part .. " edition file to vocabulary lint")
end
os.exit(t.summary() and 0 or 1)
