local ns = require("AppKit")
local xml = require("ui.xml")
local Model = require("examples.mail.Model")

local Controller = {}

local MAILBOX_W = 180
local MSG_W     = 280

-- Renders the three-pane layout and returns the window.
function Controller.createWindow()
	local selectedMailbox = Model.mailboxes[1]
	local detailPane = ns.VStack { flexGrow = 1 }

	local function showDetail(msg)
		if not msg then return end
		Model.markRead(msg.id)
		detailPane:clearContainer()
		local view = xml.renderFile("examples/mail/views/MessageDetail.xml", msg)
		detailPane:add(view)
		detailPane:layout()
	end

	-- message list (centre pane)
	local function makeMessageList(mailboxId)
		local rows = Model.byMailbox(mailboxId)
		local listRows = {}
		for _, msg in ipairs(rows) do
			listRows[#listRows + 1] = {
				_id      = msg.id,
				from     = msg.from,
				subject  = msg.subject,
				date     = msg.date,
				_preview = msg.preview,
			}
		end

		local list = ns.List {
			flexGrow = 1,
			header = false,
			alternatingRows = false,
			style = "plain",
			columns = {
				{ id = "from",    title = "From",    width = MSG_W - 4 },
			},
			data = listRows,
		}
		list:onRowSelect(function(_, _, row)
			if row and row._id then showDetail(Model.find(row._id)) end
		end)
		return list
	end

	-- mailbox sidebar
	local mailboxRows = {}
	for _, mb in ipairs(Model.mailboxes) do
		mailboxRows[#mailboxRows + 1] = {
			_id  = mb.id,
			name = mb.name,
			icon = mb.icon,
		}
	end

	local msgPane = ns.VStack { flexGrow = 0, fixedWidth = MSG_W }
	local currentList = makeMessageList(selectedMailbox.id)
	msgPane:add(currentList)

	local mailboxList = ns.List {
		fixedWidth = MAILBOX_W,
		header = false,
		style = "sourceList",
		columns = {
			{ id = "name", title = "Mailbox" },
		},
		data = mailboxRows,
	}
	mailboxList:onRowSelect(function(_, _, row)
		if not row or not row._id then return end
		msgPane:clearContainer()
		currentList = makeMessageList(row._id)
		msgPane:add(currentList)
		msgPane:layout()
		detailPane:clearContainer()
		detailPane:layout()
	end)

	-- select first message on load
	showDetail(Model.find(1))

	return ns.Window {
		title = "Mail",
		width  = MAILBOX_W + MSG_W + 480,
		height = 520,
		minWidth  = 640,
		minHeight = 400,
		toolbar = {
			{
				id = "compose",
				label = "Compose",
				icon = "square.and.pencil",
				tooltip = "New Message",
				action = function()
					Model.addMessage {
						mailbox  = selectedMailbox.id,
						from     = "Me",
						initials = "ME",
						subject  = "Untitled",
						preview  = "",
						date     = "Now",
						unread   = false,
						body     = "",
					}
					msgPane:clearContainer()
					currentList = makeMessageList(selectedMailbox.id)
					msgPane:add(currentList)
					msgPane:layout()
				end,
			},
		},
		ns.HSplit {
			mailboxList,
			msgPane,
			detailPane,
		},
	}
end

return Controller
