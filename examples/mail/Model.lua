local App = require("App")
local xml = require("ui.xml")

local Model = {}

local mailSchema = {
	root = "mail",
	fields = {
		mailboxes = {
			path = "mailboxes/mailbox",
			array = true,
			fields = {
				id = { attr = "id", type = "string" },
				name = { attr = "name", type = "string" },
				icon = { attr = "icon", type = "string" },
				count = { attr = "count", type = "number", default = 0 },
			},
		},
		messages = {
			path = "messages/message",
			array = true,
			fields = {
				id = { attr = "id", type = "number" },
				mailbox = { attr = "mailbox", type = "string" },
				from = { attr = "from", type = "string" },
				initials = { attr = "initials", type = "string" },
				subject = { attr = "subject", type = "string" },
				preview = { attr = "preview", type = "string" },
				date = { attr = "date", type = "string" },
				unread = { attr = "unread", type = "boolean", default = false },
				body = { path = "body", text = true, type = "string", default = "" },
			},
		},
	},
}

local function syncMailboxCounts()
	local byId = {}
	for _, mailbox in ipairs(Model.mailboxes) do
		mailbox.count = 0
		byId[mailbox.id] = mailbox
	end
	for _, message in ipairs(Model.messages) do
		local mailbox = byId[message.mailbox]
		if mailbox then mailbox.count = mailbox.count + 1 end
	end
	return byId
end

local function loadData()
	local data = xml.decodeFile(App.sharePath("messages.xml"), mailSchema)
	local mailboxes = data.mailboxes or {}
	local messages = data.messages or {}
	table.sort(messages, function(a, b)
		return (a.id or 0) < (b.id or 0)
	end)
	assert(#mailboxes > 0, "mail: expected at least one mailbox in share/messages.xml")
	assert(#messages > 0, "mail: expected at least one message in share/messages.xml")
	return mailboxes, messages
end

Model.mailboxes, Model.messages = loadData()
local mailboxIndex = syncMailboxCounts()

function Model.byMailbox(id)
	local result = {}
	for _, m in ipairs(Model.messages) do
		if m.mailbox == id then result[#result + 1] = m end
	end
	return result
end

function Model.find(id)
	local numeric = tonumber(id)
	for _, m in ipairs(Model.messages) do
		if m.id == numeric then return m end
	end
end

function Model.markRead(id)
	local m = Model.find(id)
	if m then m.unread = false end
end

function Model.addMessage(msg)
	msg.id = #Model.messages + 1
	Model.messages[#Model.messages + 1] = msg
	local mailbox = mailboxIndex[msg.mailbox]
	if mailbox then mailbox.count = mailbox.count + 1 end
end

return Model
