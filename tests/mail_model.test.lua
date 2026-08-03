_G.__headless = true

local t = require("TestKit")
local App = require("App")
local Model = require("examples.mail.Model")

t.expect(App.sharePath("messages.xml"):match("tests/share/messages%.xml$") ~= nil,
	"sharePath resolves relative to the caller by default")

t.assertEqual(#Model.mailboxes, 5,
	"mail model loads mailboxes from XML")
t.assertEqual(#Model.byMailbox("inbox"), 12,
	"mail model loads inbox messages from XML")
t.expect(Model.find(7).body:find("Progress:\n") ~= nil,
	"mail model preserves multiline message bodies")
t.expect(not Model.find(7).body:find("&#10;", 1, true),
	"mail model does not leak escaped newline entities into message bodies")

Model.addMessage {
	mailbox = "drafts",
	from = "Me",
	initials = "ME",
	subject = "XML-backed compose",
	preview = "",
	date = "Now",
	unread = false,
	body = "Hello\nWorld",
}

t.assertEqual(#Model.byMailbox("drafts"), 4,
	"mail model appends composed messages in memory")
t.assertEqual(Model.mailboxes[3].count, 4,
	"mail model keeps mailbox counts in sync after compose")

os.exit(t.summary() and 0 or 1)