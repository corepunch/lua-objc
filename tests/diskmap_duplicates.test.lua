_G.__headless = true
local t = require("TestKit")
local native = require("StorageScan")
local Duplicates = require("apps.diskmap.helpers.Duplicates")

-- The native search compares contents, never follows hard links, and
-- reports what removing each copy would free.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/duplicates.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local function write(path, text) local f = assert(io.open(path, "wb")); f:write(text); f:close() end
os.execute("/bin/mkdir -p " .. root .. "/Documents " .. root .. "/Downloads")
local body = string.rep("report ", 20000)
write(root .. "/Documents/report.pdf", body)
write(root .. "/Downloads/report.pdf", body)
write(root .. "/Downloads/report (1).pdf", body:sub(1, -2) .. "!")
write(root .. "/Downloads/tiny.txt", "same")
write(root .. "/Documents/tiny.txt", "same")
local function q(path) return "'" .. path .. "'" end
os.execute("/bin/cp -c " .. q(root .. "/Documents/report.pdf") .. " " .. q(root .. "/Documents/report clone.pdf"))
os.execute("/bin/ln " .. q(root .. "/Documents/report.pdf") .. " " .. q(root .. "/Documents/report link.pdf"))
local result = native.duplicates({root}, {minimumBytes = 1000})
t.assertEqual(#result.groups, 1, "only files with identical contents form a group")
local group = result.groups[1]
t.assertEqual(#group.files, 3, "a hard link is the same file, not a copy")
local paths = {}
for _, file in ipairs(group.files) do paths[file.path:sub(#root + 2)] = file end
t.expect((paths["Documents/report.pdf"] or paths["Documents/report link.pdf"]) and paths["Downloads/report.pdf"]
	and paths["Documents/report clone.pdf"], "copies and clones are found; a linked file appears once under either name")
t.expect(paths["Documents/report clone.pdf"].privateBytes == 0, "a clone that shares every block frees nothing")
t.expect(group.reclaimable >= #body and group.reclaimable < 2 * #body, "reclaimable space counts only unshared blocks")
t.expect(#native.duplicates({root}, {minimumBytes = 1}).groups == 2, "a smaller minimum includes small files")
local job = native.duplicatesStart({root}, {minimumBytes = 1000})
local done, snapshot
for _ = 1, 200 do done, snapshot = native.duplicatesPoll(job); if done then break end; os.execute("sleep 0.01") end
t.expect(done and #snapshot.groups == 1, "the background search reports the same groups")
os.execute("/bin/rm -rf " .. root)

-- The model keeps one copy per group and marks the rest.
local sample = {bytes = 100, reclaimable = 200, files = {
	{path = "/Users/me/Downloads/a.pdf", privateBytes = 100},
	{path = "/Users/me/Documents/Work/a.pdf", privateBytes = 100},
	{path = "/Users/me/Desktop/a.pdf", privateBytes = 100},
}}
local items, keep = Duplicates.copies(sample)
t.assertEqual(keep.path, "/Users/me/Documents/Work/a.pdf", "the copy outside Downloads and Desktop is kept")
t.assertEqual(#items, 2, "every other copy is offered for cleanup")
local rows = Duplicates.rows({sample}, "", "/Users/me")
t.expect(rows[1].detail == "3 copies" and rows[1].subtitle:find("~/Documents/Work", 1, true), "rows say how many copies and which stays")
t.assertEqual(#Duplicates.rows({sample}, "nothing"), 0, "search filters by name")
local summary = Duplicates.summary({sample})
t.expect(summary.copies == 2 and summary.bytes == 200, "the summary totals what could be freed")

-- The page reads nothing until a folder is added and a search started.
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")
local service = Mock.new()
local searched = 0
local find = service.findDuplicates
service.findDuplicates = function(...) searched = searched + 1; return find(...) end
service.pickFolder = function() return service.home .. "/Library" end
local app = Controller.new(service)
app:createWindow()
app:show("duplicates")
local page = app.pages.duplicates
t.expect(not page.refs.search.enabled and page.refs.duplicatesList.hidden, "with no folder there is nothing to search")
page.actions.addFolder()
t.expect(page.refs.search.enabled and page.refs.duplicateRoots.text:find("~/Library", 1, true), "an added folder can be searched")
t.assertEqual(searched, 0, "adding a folder reads nothing")
page.actions.search()
t.assertEqual(searched, 1, "Find Duplicates searches the added folders")
t.expect(service.loadFolders("duplicates")[1] == service.home .. "/Library", "added folders are remembered")

-- Empty states are told apart: nothing chosen, not searched yet, searched
-- with no duplicates, filtered away, failed. A running search is not one: the
-- page computes, with a single spinner, until the result arrives.
t.assertEqual(Duplicates.state({}, nil, 0), "choose", "no folder chosen invites a choice")
t.assertEqual(Duplicates.state({"/a"}, nil, 0), "ready", "a chosen folder that was never searched is ready, not empty")
t.assertEqual(Duplicates.state({"/a"}, {groups = {}}, 0), "none", "a finished search with no groups found none")
t.assertEqual(Duplicates.state({"/a"}, {groups = {{}}}, 0, "zzz"), "nomatch", "a filter that hides every group is no match, not no duplicates")
t.assertEqual(Duplicates.state({"/a"}, {groups = {{}}}, 2), "list", "groups are listed")
t.assertEqual(Duplicates.state({"/a"}, {failure = "denied"}, 0), "failed", "a failed search is a failure, not an empty result")
t.assertEqual(Duplicates.state({"/a"}, {}, 0), "failed", "a result without groups is a failure")
os.exit(t.summary() and 0 or 1)
