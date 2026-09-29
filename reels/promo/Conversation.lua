-- The agent's side of the promo: the diff lines of each edit, read from its
-- patch, and the Lua Studio conversation after k edits. The reel draws the
-- same lines the Studio capture shows, so the source on screen is always
-- the change that produced the picture.
local Conversation = {}

-- lines(path) -> the changed and context lines of a unified diff, without
-- file headers or hunk markers, indentation folded to one space so they fit
-- a chat bubble: {"+<GroupBox id=\"progress\">", " <VStack …>", …}.
function Conversation.lines(path)
	local file = assert(io.open(path, "r"))
	local lines = {}
	for line in file:lines() do
		if not (line:match("^%-%-%- ") or line:match("^%+%+%+ ") or line:match("^@@")) then
			local sign, body = line:sub(1, 1), line:sub(2)
			body = body:gsub("^%s+", "")
			table.insert(lines, { sign = sign, text = body })
		end
	end
	file:close()
	return lines
end

-- The changed file's name and its "+added −removed" counts.
function Conversation.summary(path)
	local file = assert(io.open(path, "r"))
	local name, added, removed = nil, 0, 0
	for line in file:lines() do
		name = name or line:match("^%+%+%+ b/(.+)$")
		if line:match("^%+") and not line:match("^%+%+%+") then added = added + 1 end
		if line:match("^%-") and not line:match("^%-%-%-") then removed = removed + 1 end
	end
	file:close()
	return name, added, removed
end

-- Only changed lines, then the context around them, up to `limit`.
local function excerpt(lines, limit)
	local out = {}
	for _, line in ipairs(lines) do
		if line.sign == "+" or line.sign == "-" then
			if #out >= limit then break end
			table.insert(out, line.sign .. " " .. line.text)
		end
	end
	return out
end

local CHAT = { lines = 9 }

-- showcase(app, k, editsDir) -> Lua source for LUA_STUDIO_SHOWCASE: the
-- project, its files, the exchanges for edits 1…k (each agent turn with a
-- change card carrying the diff lines) and the next edit's prompt as the
-- draft.
function Conversation.showcase(app, k, editsDir)
	local out = { "return {", string.format("\tproject = %q,", app.dir),
		string.format("\tcurrent = {title = %q, icon = %q},", app.title or app.dir, app.icon or "app.fill"), "\tfiles = {" }
	for _, name in ipairs(app.files) do table.insert(out, string.format("\t\t%q,", name)) end
	table.insert(out, "\t},")
	table.insert(out, "\tconversation = {")
	table.insert(out, string.format("\t\tstatus = %q,", k > 0 and "Reloaded · no build" or "Ready"))
	table.insert(out, string.format("\t\tdraft = %q,", app.edits[k + 1] and app.edits[k + 1].prompt or ""))
	table.insert(out, "\t\tmessages = {")
	for i = 1, k do
		local edit = app.edits[i]
		local path = editsDir .. edit.patch .. ".patch"
		local name, added, removed = Conversation.summary(path)
		table.insert(out, string.format("\t\t\t{role = \"user\", text = %q},", edit.prompt))
		table.insert(out, string.format("\t\t\t{role = \"agent\", text = %q, changes = {", edit.reply))
		table.insert(out, string.format("\t\t\t\t{path = %q, added = %d, removed = %d, lines = {",
			name:sub(#app.dir + 2), added, removed))
		for _, line in ipairs(excerpt(Conversation.lines(path), CHAT.lines)) do
			table.insert(out, string.format("\t\t\t\t\t%q,", line))
		end
		table.insert(out, "\t\t\t\t}},")
		table.insert(out, "\t\t\t}},")
	end
	table.insert(out, "\t\t},")
	table.insert(out, "\t},")
	table.insert(out, "}")
	return table.concat(out, "\n") .. "\n"
end

return Conversation
