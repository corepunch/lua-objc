-- The agent's side of the promo: the files each edit changes, read from its
-- patch, and the Lua Studio conversation after k edits. The reel draws the
-- same lines the Studio capture shows, so the source on screen is always
-- the change that produced the picture.
local Conversation = {}

-- files(path) -> the files a unified diff changes, in its order:
-- {{path = "demo/todo/Model.lua", added, removed, lines = {{sign, text}…}}…}.
-- Lines are the changed and context lines without hunk markers,
-- indentation folded to one space so they fit a chat card.
function Conversation.files(path)
	local file = assert(io.open(path, "r"))
	local files, current = {}, nil
	for line in file:lines() do
		local name = line:match("^%+%+%+ b/(.+)$")
		if name then
			current = { path = name, added = 0, removed = 0, lines = {} }
			table.insert(files, current)
		elseif current and not (line:match("^%-%-%- ") or line:match("^@@")) then
			local sign, body = line:sub(1, 1), line:sub(2)
			if sign == "+" then current.added = current.added + 1 end
			if sign == "-" then current.removed = current.removed + 1 end
			table.insert(current.lines, { sign = sign, text = (body:gsub("^%s+", "")) })
		end
	end
	file:close()
	return files
end

-- Changed lines of code, up to `limit`: blank lines and Lua comments are
-- left out, so a short excerpt shows what the edit does.
function Conversation.excerpt(lines, limit)
	local out = {}
	for _, line in ipairs(lines) do
		if (line.sign == "+" or line.sign == "-") and line.text ~= "" and not line.text:match("^%-%-") then
			if #out >= limit then break end
			table.insert(out, line.sign .. " " .. line.text)
		end
	end
	return out
end

-- A change card holds this many diff lines in all, shared between its
-- files, so an edit to three files reads as compactly as one to one file.
local CHAT = { lines = 9 }

-- showcase(app, k, editsDir) -> Lua source for LUA_STUDIO_SHOWCASE: the
-- project, its files, the exchanges for edits 1…k (each agent turn with a
-- change card carrying every changed file and its diff lines) and the next
-- edit's prompt as the draft.
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
		local files = Conversation.files(editsDir .. edit.patch .. ".patch")
		table.insert(out, string.format("\t\t\t{role = \"user\", text = %q},", edit.prompt))
		table.insert(out, string.format("\t\t\t{role = \"agent\", text = %q, changes = {", edit.reply))
		for _, file in ipairs(files) do
			table.insert(out, string.format("\t\t\t\t{path = %q, added = %d, removed = %d, lines = {",
				file.path:sub(#app.dir + 2), file.added, file.removed))
			for _, line in ipairs(Conversation.excerpt(file.lines, math.floor(CHAT.lines / #files))) do
				table.insert(out, string.format("\t\t\t\t\t%q,", line))
			end
			table.insert(out, "\t\t\t\t},")
			table.insert(out, "\t\t\t\t},")
		end
		table.insert(out, "\t\t\t}},")
	end
	table.insert(out, "\t\t},")
	table.insert(out, "\t},")
	table.insert(out, "}")
	return table.concat(out, "\n") .. "\n"
end

return Conversation
