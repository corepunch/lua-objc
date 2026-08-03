local t = require("TestKit")
local xml = require("ui.xml")

local source = [=[
<?xml version="1.0" encoding="UTF-8"?>
<mail>
	<mailboxes>
		<mailbox id="inbox" name="Inbox" count="12" />
		<mailbox id="archive" name="Archive" count="4" />
	</mailboxes>
	<messages>
		<message id="7" unread="true" mailbox="inbox">
			<body><![CDATA[Progress:
80% complete]]></body>
		</message>
		<message id="8" unread="false" mailbox="archive">
			<body>Done &amp; shipped</body>
		</message>
	</messages>
</mail>
]=]

local schema = {
	root = "mail",
	fields = {
		mailboxes = {
			path = "mailboxes/mailbox",
			array = true,
			fields = {
				id = "@id",
				name = "@name",
				count = { attr = "count", type = "number", default = 0 },
			},
		},
		messages = {
			path = "messages/message",
			array = true,
			fields = {
				id = { attr = "id", type = "number" },
				mailbox = "@mailbox",
				unread = { attr = "unread", type = "boolean" },
				body = { path = "body", text = true, type = "string", default = "" },
			},
		},
	},
}

local data = xml.decode(source, schema)

t.assertEqual(#data.mailboxes, 2, "decode reads mailbox array")
t.assertEqual(data.mailboxes[1].id, "inbox", "decode reads attribute shorthand")
t.assertEqual(data.mailboxes[1].count, 12, "decode coerces number types")
t.assertEqual(#data.messages, 2, "decode reads message array")
t.assertEqual(data.messages[1].id, 7, "decode coerces numeric ids")
t.expect(data.messages[1].unread == true, "decode coerces boolean true")
t.expect(data.messages[1].body:find("Progress:\n80%% complete") ~= nil,
	"decode preserves multiline CDATA text")
t.assertEqual(data.messages[2].body, "Done & shipped", "decode resolves XML entities in text")

local minimal = xml.decode("<root><item id='x' /></root>", {
	root = "root",
	fields = {
		items = {
			path = "item",
			array = true,
			fields = {
				id = "@id",
				count = { attr = "count", type = "number", default = 0 },
			},
		},
	},
})

t.assertEqual(minimal.items[1].count, 0, "decode applies default values for missing attrs")

os.exit(t.summary() and 0 or 1)
