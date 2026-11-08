-- What the Studio capsule says on a phone: the conversation folded to one
-- line, as Music folds the player to the song that plays. Pure: it reads
-- the messages, the state of the agent and the project it is given.
local Chat = require("apps.studio.helpers.Chat")
local Capsule = {}

local function firstLine(text)
	return tostring(text or ""):match("^%s*([^\n]*)") or ""
end

-- The trailing agent turn: every agent message since the last request.
local function lastTurn(messages)
	local turn = {}
	for index = #messages, 1, -1 do
		local message = messages[index]
		if message.role ~= "agent" then break end
		table.insert(turn, 1, message)
	end
	return turn
end

-- The files a turn changed, one row per path however many saves touched it.
local function changesOf(turn)
	local byPath, result, failed = {}, {}, false
	for _, message in ipairs(turn) do
		if message.previewState == "error" then failed = true end
		for _, change in ipairs(message.changes or {}) do
			local row = byPath[change.path]
			if not row then
				row = { path = change.path, added = 0, removed = 0 }
				byPath[change.path] = row
				table.insert(result, row)
			end
			row.added, row.removed = row.added + (change.added or 0), row.removed + (change.removed or 0)
		end
	end
	return result, failed
end

-- `state`: {messages, busy, project, modelId, previewError}. The result is
-- {title, detail} with `busy` while the agent works and `failed` when the
-- last thing that happened went wrong.
function Capsule.status(state)
	local messages = state.messages or {}
	if not state.project then return { title = "No project", detail = "Tap to create one" } end
	if state.busy then
		local request = ""
		for index = #messages, 1, -1 do
			if messages[index].role == "user" then request = firstLine(messages[index].text); break end
		end
		return { title = "Working…", detail = request, busy = true }
	end
	local last = messages[#messages]
	if last and last.role == "error" then
		return { title = "Something went wrong", detail = firstLine(last.text), failed = true }
	end
	local turn = lastTurn(messages)
	local changes, failed = changesOf(turn)
	if #changes > 0 then
		local _, summary = Chat.changes(changes)
		if failed then
			return { title = "Preview failed", detail = summary.title .. ". Last working version kept. Tap to fix.", failed = true }
		end
		return { title = "Preview updated", detail = summary.title .. ", " .. summary.delta .. ". Tap to review." }
	end
	if state.previewError then
		return { title = "Preview failed", detail = firstLine(state.previewError), failed = true }
	end
	if #turn > 0 then
		return { title = firstLine(turn[#turn].text), detail = "Tap to continue" }
	end
	return { title = "Ask to change anything", detail = state.project.title .. " · " .. (state.modelId or "") }
end

return Capsule
