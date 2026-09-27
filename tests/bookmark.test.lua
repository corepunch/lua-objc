_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

-- Bookmarks follow a folder through renames and survive as plain text.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/bookmark.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
os.execute("/bin/mkdir " .. root .. "/Projects")
local text = ns.bookmark(root .. "/Projects")
t.expect(type(text) == "string" and #text > 16, "a folder can be bookmarked as text")
local path, stale = ns.resolveBookmark(text)
t.assertEqual(path, root .. "/Projects", "a bookmark resolves to its folder")
t.expect(stale == false, "a fresh bookmark is not stale")
os.rename(root .. "/Projects", root .. "/Code")
t.assertEqual((ns.resolveBookmark(text)), root .. "/Code", "a bookmark follows a renamed folder")
local missing, _, message = ns.resolveBookmark("bm90IGEgYm9va21hcms=")
t.expect(missing == nil and type(message) == "string", "an invalid bookmark reports why")
os.execute("/bin/rm -rf " .. root)
os.exit(t.summary() and 0 or 1)
