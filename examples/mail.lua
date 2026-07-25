local ns = require("AppKit")

local inbox = {
	{ from = "Alice Chen",    subject = "Q3 roadmap review",            date = "10:32 AM" },
	{ from = "Bob Martinez",  subject = "Design system updates",         date = "9:15 AM" },
	{ from = "Carol Park",    subject = "Meeting notes from yesterday",  date = "Yesterday" },
	{ from = "Dave Johnson",  subject = "PR #142 ready for review",      date = "Yesterday" },
	{ from = "Eve Williams",  subject = "Budget approval needed",        date = "Mon" },
	{ from = "Frank Brown",   subject = "Welcome to the team!",          date = "Mon" },
	{ from = "Grace Kim",     subject = "API migration progress",        date = "Sun" },
	{ from = "Henry Davis",   subject = "Weekly standup notes",          date = "Sun" },
}

local folders = {
	{ name = "Inbox",     count = "8" },
	{ name = "Sent",      count = "" },
	{ name = "Drafts",    count = "3" },
	{ name = "Archive",   count = "" },
	{ name = "Trash",     count = "" },
}

local message_list = ns.List {
	width = 460,
	height = 310,
	columns = {
		{ id = "from",    title = "From" },
		{ id = "subject", title = "Subject" },
		{ id = "date",    title = "Date" },
	},
	data = inbox,
}

local folder_list = ns.List {
	width = 170,
	height = 310,
	header = false,
	columns = {
		{ id = "name",  title = "", width = 125 },
		{ id = "count", title = "", width = 45, alignment = "trailing" },
	},
	data = folders,
}

ns.Window {
	title = "Mail",
	width = 680,
	height = 420,
	toolbar = {
		{
			id = "new",
			label = "New",
			icon = "square.and.pencil",
			tooltip = "Compose a new message",
			action = function()
				message_list:addRow{
					from = "Me",
					subject = "Untitled message",
					date = "Now",
				}
			end,
		},
	},
	ns.HSplit {
		folder_list,
		message_list,
	},
}
