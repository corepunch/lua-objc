_G.__headless = true
local t = require("TestKit")
local Locations = require("apps.diskmap.knowledge.Locations")
local Categories = require("apps.diskmap.knowledge.Categories")
local Builds = require("apps.diskmap.knowledge.Builds")
local Manifest = require("data.manifest")

-- The dictionary (VISION.md): one line per folder, dated, with an owner,
-- a sentence and a verdict from a small vocabulary. Twenty-odd tools, not
-- two hundred.
local categories = {}
for _, category in ipairs(Categories) do categories[category.id] = category end
local REMOVE = {safe = true, review = true, owner = true, system = true}
local seen = {}
for _, entry in ipairs(Locations.list) do
	local where = entry.path
	t.expect(categories[entry.category] ~= nil, where .. " names a category")
	t.expect(type(entry.section) == "string", where .. " names a section")
	t.expect(entry.path:match("^[/~$]") ~= nil, where .. " is absolute, home-relative or TMPDIR-relative")
	t.expect(type(entry.name) == "string" and entry.name ~= "", where .. " has a name")
	t.expect(type(entry.owner) == "string" and entry.owner ~= "", where .. " has an owner")
	t.expect(type(entry.what) == "string" and #entry.what > 20 and entry.what:match("%.$"), where .. " explains itself in a sentence")
	t.expect(REMOVE[entry.remove], where .. " uses the verdict vocabulary")
	t.expect(type(entry.checked) == "string" and entry.checked:match("^%d%d%d%d%-%d%d$"), where .. " says when it was checked")
	t.expect(not (seen[entry.path] and seen[entry.path] ~= entry.category), where .. " is listed by one category")
	seen[entry.path] = entry.category
	for name, child in pairs(entry.children or {}) do
		t.expect(entry.expand, where .. " lists children only when expanded")
		t.expect(REMOVE[child.remove] and type(child.what) == "string", where .. "/" .. name .. " is described")
	end
end
t.expect(#Locations.list >= 60 and #Locations.list <= 140, "the dictionary stays small: " .. #Locations.list .. " entries")
t.expect(#Locations.of("system") >= 8, "System Data is decomposed")
t.expect(#Locations.of("ai") >= 10, "the AI long tail is covered")
local safe = 0
for _, entry in ipairs(Locations.list) do if entry.remove == "safe" then safe = safe + 1 end end
t.expect(safe >= 30, "most of the dictionary is caches Diskmap can remove")

-- The sidebar and the knowledge agree on the sources: same ids, icons,
-- colors and keys, so the sidebar, the Go menu and the page never disagree.
local manifest = Manifest.load("apps/diskmap/app.xml")
for _, category in ipairs(Categories) do
	local page = manifest.pages[category.id]
	t.expect(page ~= nil, "the manifest has a page for " .. category.id)
	if page then
		t.assertEqual(page.attrs.category, category.id, category.id .. " page names its category")
		t.assertEqual(page.icon, category.icon, category.id .. " icon matches")
		t.assertEqual(page.color, category.color, category.id .. " color matches")
		t.assertEqual(page.key, category.key, category.id .. " key matches")
		t.assertEqual(page.title, category.title, category.id .. " title matches")
	end
	t.expect(type(category.summary) == "string" and type(category.empty) == "string", category.id .. " has a summary and an empty text")
end

-- Build rules: every rule has a folder name, markers and a sentence; names
-- the search prunes include every rule's folder.
local skip = {}
for _, name in ipairs(Builds.skip) do skip[name] = true end
for _, rule in ipairs(Builds.rules) do
	t.expect(#rule.markers > 0 and type(rule.inner) == "table", rule.dirName .. " has markers and inner proofs")
	t.expect(type(rule.what) == "string" and rule.what:match("%.$"), rule.dirName .. " says what it is")
	t.expect(skip[rule.dirName], "the search never descends into " .. rule.dirName)
end
t.expect(#Builds.dirNames() < #Builds.rules, "several rules share a folder name")

os.exit(t.summary() and 0 or 1)
