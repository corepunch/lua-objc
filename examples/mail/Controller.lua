local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.mail.Model")

local VIEWS = "examples/mail/views/"

local ACTIONS = {
	compose = function(self) self:compose() end,
}

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

function WindowController:showDetail(msg)
	if not msg then return end
	Model.markRead(msg.id)
	self.detailPane:clearContainer()
	local view = xml.renderFile(VIEWS .. "MessageDetail.etlua", msg)
	self.detailPane:add(view)
	self.detailPane:layout()
end

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
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	self.mailboxList = refs.mailboxList
	self.messageList = refs.messageList
	self.detailPane  = refs.detailPane

	local mailboxRows = {}
	for _, mb in ipairs(Model.mailboxes) do
		mailboxRows[#mailboxRows + 1] = { _id = mb.id, name = mb.name, icon = mb.icon }
	end
	self.mailboxList:replaceRows(mailboxRows)

	self.mailboxList:onRowSelect(function(_, _, row)
		if not row or not row._id then return end
		self.selectedMailbox = { id = row._id }
		self:loadMessages(row._id)
		self.detailPane:clearContainer()
		self.detailPane:layout()
	end)

	self:loadMessages(self.selectedMailbox.id)

	self.messageList:onRowSelect(function(_, _, row)
		if row and row._id then self:showDetail(Model.find(row._id)) end
	end)

	self:showDetail(Model.find(1))

	self.window = ns.Window(cfg)
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
