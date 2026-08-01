local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.mail.Model")

local VIEWS = "examples/mail/views/"

-- WindowController owns the window lifetime and all action handlers.
-- It is an object rather than a module-level function so that closures
-- can reference self.* instead of upvalue variables, and so that the
-- class boundary is explicit when more scenes are added later.
local WindowController = {}
WindowController.__index = WindowController

function WindowController.new()
	return setmetatable({
		selectedMailbox = Model.mailboxes[1],
		mailboxList     = nil,
		messageList     = nil,
		detailPane      = nil,
		window          = nil,
	}, WindowController)
end

-- Rebuild the detail pane from a MessageDetail template.
function WindowController:showDetail(msg)
	if not msg then return end
	Model.markRead(msg.id)
	self.detailPane:clearContainer()
	local view = xml.renderFile(VIEWS .. "MessageDetail.xml", msg)
	self.detailPane:add(view)
	self.detailPane:layout()
end

-- Reload the message list for the given mailbox id.
function WindowController:loadMessages(mailboxId)
	local rows = {}
	for _, msg in ipairs(Model.byMailbox(mailboxId)) do
		rows[#rows + 1] = {
			_id     = msg.id,
			from    = msg.from,
			subject = msg.subject,
			date    = msg.date,
		}
	end
	self.messageList:replaceRows(rows)
end

function WindowController:createWindow()
	-- Render the chrome: three-pane HSplit with named refs for each pane.
	local layout, refs = xml.renderFile(VIEWS .. "MailLayout.xml")

	self.mailboxList = refs.mailboxList
	self.messageList = refs.messageList
	self.detailPane  = refs.detailPane

	-- Populate mailbox sidebar.
	local mailboxRows = {}
	for _, mb in ipairs(Model.mailboxes) do
		mailboxRows[#mailboxRows + 1] = { _id = mb.id, name = mb.name, icon = mb.icon }
	end
	self.mailboxList:replaceRows(mailboxRows)

	-- Wire mailbox selection → reload message list + clear detail.
	self.mailboxList:onRowSelect(function(_, _, row)
		if not row or not row._id then return end
		self.selectedMailbox = Model.find and { id = row._id } or { id = row._id }
		self:loadMessages(row._id)
		self.detailPane:clearContainer()
		self.detailPane:layout()
	end)

	-- Populate initial message list.
	self:loadMessages(self.selectedMailbox.id)

	-- Wire message selection → show detail.
	self.messageList:onRowSelect(function(_, _, row)
		if row and row._id then self:showDetail(Model.find(row._id)) end
	end)

	-- Show the first message on load.
	self:showDetail(Model.find(1))

	self.window = ns.Window {
		title     = "Mail",
		width     = 180 + 280 + 480,
		height    = 520,
		minWidth  = 640,
		minHeight = 400,
		toolbar   = {
			{
				id      = "compose",
				label   = "Compose",
				icon    = "square.and.pencil",
				tooltip = "New Message",
				action  = function() self:compose() end,
			},
		},
		layout,
	}
	return self.window
end

function WindowController:compose()
	Model.addMessage {
		mailbox  = self.selectedMailbox.id,
		from     = "Me",
		initials = "ME",
		subject  = "Untitled",
		preview  = "",
		date     = "Now",
		unread   = false,
		body     = "",
	}
	self:loadMessages(self.selectedMailbox.id)
end

return WindowController
