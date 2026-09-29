-- The promo reel's agent edits (reels/promo/Edits.lua, edits/*.patch):
-- every patch still reverse-applies to the app as it is in the repository,
-- in order, so each version the reel captures can be rebuilt; each patch
-- really changes its app; and the Lua Studio showcase built from them loads.
_G.__headless = true
package.path = "reels/promo/?.lua;" .. package.path

local t = require("TestKit")
local Edits = require("Edits")
local Conversation = require("Conversation")

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local dir = os.tmpname()
os.remove(dir)

for name, app in pairs(Edits) do
	local root = dir .. "/" .. name
	os.execute("mkdir -p " .. quote(root .. "/demo") .. " && cp -R " .. quote(app.dir) .. " " .. quote(root .. "/" .. app.dir))
	for i = #app.edits, 1, -1 do
		local patch = "reels/promo/edits/" .. app.edits[i].patch .. ".patch"
		t.expect(io.open(patch) ~= nil, patch .. " exists")
		local ok = os.execute("patch -s -R -p1 --dry-run -d " .. quote(root) .. " < " .. quote(patch) .. " >/dev/null 2>&1")
		t.expect(ok, name .. ": " .. app.edits[i].patch .. " reverse-applies to version " .. i)
		os.execute("patch -s -R -p1 -d " .. quote(root) .. " < " .. quote(patch) .. " >/dev/null 2>&1")
		local file, added, removed = Conversation.summary(patch)
		t.expect(file and file:find(app.dir, 1, true) == 1, app.edits[i].patch .. " edits " .. app.dir)
		t.expect(added + removed > 0, app.edits[i].patch .. " changes lines")
		t.expect(app.edits[i].prompt:match("%.$") and #app.edits[i].reply > 0, app.edits[i].patch .. " has a prompt and a reply")
	end
	local same = os.execute("/usr/bin/diff -rq " .. quote(app.dir) .. " " .. quote(root .. "/" .. app.dir) .. " >/dev/null")
	t.expect(not same, name .. ": version 0 differs from the shipped app")
end

local lines = Conversation.lines("reels/promo/edits/todo-2-progress.patch")
t.assertEqual(lines[1].sign, " ", "diff lines keep context")
local added = 0
for _, line in ipairs(lines) do if line.sign == "+" then added = added + 1 end end
t.assertEqual(added, 10, "the progress edit adds ten lines")
t.expect(lines[4].text:find("^<GroupBox"), "indentation is folded away")

for k = 0, #Edits.todo.edits do
	local source = Conversation.showcase(Edits.todo, k, "reels/promo/edits/")
	local data = assert(load(source, "=showcase", "t", {}))()
	t.assertEqual(data.project, "demo/todo", "the showcase opens Todo (v" .. k .. ")")
	t.assertEqual(#data.conversation.messages, k * 2, "one exchange per edit so far (v" .. k .. ")")
	t.assertEqual(data.conversation.draft, Edits.todo.edits[k + 1] and Edits.todo.edits[k + 1].prompt or "",
		"the next prompt waits in the composer (v" .. k .. ")")
	for _, file in ipairs(data.files) do
		t.expect(io.open("demo/todo/" .. file) ~= nil, "showcase file demo/todo/" .. file .. " exists")
	end
end

os.execute("rm -rf " .. quote(dir))
os.exit(t.summary() and 0 or 1)
