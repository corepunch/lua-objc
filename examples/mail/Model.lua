local Model = {}

Model.mailboxes = {
	{ id = "inbox",   name = "Inbox",   icon = "tray",                count = 8  },
	{ id = "sent",    name = "Sent",    icon = "paperplane",          count = 0  },
	{ id = "drafts",  name = "Drafts",  icon = "doc",                 count = 3  },
	{ id = "archive", name = "Archive", icon = "archivebox",          count = 0  },
	{ id = "trash",   name = "Trash",   icon = "trash",               count = 0  },
}

Model.messages = {
	{
		id = 1, mailbox = "inbox",
		from = "Alice Chen",   initials = "AC",
		subject = "Q3 roadmap review",
		preview = "Can we align on the roadmap before the board meeting?",
		date = "10:32 AM", unread = true,
		body = "Hi,\n\nCan we align on the roadmap before the board meeting on Thursday?\n\nBest,\nAlice",
	},
	{
		id = 2, mailbox = "inbox",
		from = "Bob Martinez",  initials = "BM",
		subject = "Design system updates",
		preview = "I've pushed the new token set to Figma.",
		date = "9:15 AM", unread = true,
		body = "Hi team,\n\nI've pushed the new token set to Figma — please review the spacing changes.\n\nThanks,\nBob",
	},
	{
		id = 3, mailbox = "inbox",
		from = "Carol Park",    initials = "CP",
		subject = "Meeting notes from yesterday",
		preview = "Attaching the notes from our sync.",
		date = "Yesterday", unread = false,
		body = "Here are the notes from yesterday's sync.\n\n• Agreed on v2 scope\n• Bob owns design tokens\n• Alice presents to board\n\nCarol",
	},
	{
		id = 4, mailbox = "inbox",
		from = "Dave Johnson",  initials = "DJ",
		subject = "PR #142 ready for review",
		preview = "Added tests and fixed the edge case we discussed.",
		date = "Yesterday", unread = false,
		body = "PR is up: github.com/example/repo/pull/142\n\nAdded tests for the nil-path edge case.\n\nDave",
	},
	{
		id = 5, mailbox = "inbox",
		from = "Eve Williams",  initials = "EW",
		subject = "Budget approval needed",
		preview = "Please approve the Q4 tooling spend by EOD.",
		date = "Mon", unread = false,
		body = "Hi,\n\nThe Q4 tooling budget needs sign-off by end of day.\nTotal: $4,200 across design tools and CI credits.\n\nEve",
	},
	{
		id = 6, mailbox = "inbox",
		from = "Frank Brown",   initials = "FB",
		subject = "Welcome to the team!",
		preview = "So glad to have you on board.",
		date = "Mon", unread = false,
		body = "Welcome!\n\nSo glad to have you on board. Reach out any time.\n\nFrank",
	},
	{
		id = 7, mailbox = "inbox",
		from = "Grace Kim",     initials = "GK",
		subject = "API migration progress",
		preview = "We're at 80% — on track for the Friday deadline.",
		date = "Sun", unread = false,
		body = "Status update:\n\n80% of endpoints migrated.\nRemaining: /auth/refresh and /upload.\nOn track for Friday.\n\nGrace",
	},
	{
		id = 8, mailbox = "inbox",
		from = "Henry Davis",   initials = "HD",
		subject = "Weekly standup notes",
		preview = "Short summary of this week's standups.",
		date = "Sun", unread = false,
		body = "Week summary:\n\nMon: roadmap review\nTue: design tokens\nWed: PR reviews\nThu: budget\nFri: API migration\n\nHenry",
	},
}

function Model.byMailbox(id)
	local result = {}
	for _, m in ipairs(Model.messages) do
		if m.mailbox == id then result[#result + 1] = m end
	end
	return result
end

function Model.find(id)
	for _, m in ipairs(Model.messages) do
		if m.id == id then return m end
	end
end

function Model.markRead(id)
	local m = Model.find(id)
	if m then m.unread = false end
end

function Model.addMessage(msg)
	msg.id = #Model.messages + 1
	Model.messages[#Model.messages + 1] = msg
end

return Model
