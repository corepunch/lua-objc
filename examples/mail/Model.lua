local App = require("App")

local Model = {}

local function decodeXMLText(value)
	if type(value) ~= "string" or value == "" then return value end
	value = value:gsub("&#x([%da-fA-F]+);", function(hex)
		local code = tonumber(hex, 16)
		return code and utf8.char(code) or "&#x" .. hex .. ";"
	end)
	value = value:gsub("&#(%d+);", function(decimal)
		local code = tonumber(decimal, 10)
		return code and utf8.char(code) or "&#" .. decimal .. ";"
	end)
	return (value
		:gsub("&quot;", '"')
		:gsub("&apos;", "'")
		:gsub("&lt;", "<")
		:gsub("&gt;", ">")
		:gsub("&amp;", "&"))
end

local function parseAttrs(attrText)
	local attrs = {}
	for key, value in attrText:gmatch('([%w_:%-]+)%s*=%s*"([^"]*)"') do
		attrs[key] = decodeXMLText(value)
	end
	for key, value in attrText:gmatch("([%w_:%-]+)%s*=%s*'([^']*)'") do
		attrs[key] = decodeXMLText(value)
	end
	return attrs
end

local function readFile(path)
	local file = assert(io.open(path, "r"), "mail: cannot open " .. path)
	local body = file:read("*a")
	file:close()
	return body
end

local function parseBody(messageXML)
	local cdata = messageXML:match("<body>%s*<!%[CDATA%[(.-)%]%]>%s*</body>")
	if cdata then return cdata end
	local body = messageXML:match("<body>%s*(.-)%s*</body>")
	return decodeXMLText(body or "")
end

local function parseMailboxes(xml)
	local mailboxes = {}
	for attrText in xml:gmatch("<mailbox%s+([^>/]-)%s*/>") do
		local attrs = parseAttrs(attrText)
		mailboxes[#mailboxes + 1] = {
			id = attrs.id,
			name = attrs.name,
			icon = attrs.icon,
			count = tonumber(attrs.count) or 0,
		}
	end
	return mailboxes
end

local function parseMessages(xml)
	local messages = {}
	for attrText, inner in xml:gmatch("<message%s+([^>]-)%s*>(.-)</message>") do
		local attrs = parseAttrs(attrText)
		messages[#messages + 1] = {
			id = tonumber(attrs.id),
			mailbox = attrs.mailbox,
			from = attrs.from,
			initials = attrs.initials,
			subject = attrs.subject,
			preview = attrs.preview,
			date = attrs.date,
			unread = attrs.unread == "true",
			body = parseBody(inner),
		}
	end
	table.sort(messages, function(a, b)
		return (a.id or 0) < (b.id or 0)
	end)
	return messages
end

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
	local xml = readFile(App.sharePath("messages.xml"))
	local mailboxes = parseMailboxes(xml)
	local messages = parseMessages(xml)
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
