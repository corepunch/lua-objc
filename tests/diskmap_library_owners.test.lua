_G.__headless = true
local t = require("TestKit")
local Model = require("data.model")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Leftovers = require("apps.diskmap.helpers.Leftovers")
local Explain = require("apps.diskmap.helpers.Explain")
local Library = require("apps.diskmap.knowledge.Library")
local Map = require("apps.diskmap.knowledge.Filesystem")

-- Who owns a Library folder, and what it is (helpers/Explain).
local apps = {
	{bundleId = "com.microsoft.Word", name = "Microsoft Word", team = "UBF8T346G9", groups = {"UBF8T346G9.Office", "UBF8T346G9.ms"}},
	{bundleId = "com.microsoft.Excel", name = "Microsoft Excel", team = "UBF8T346G9", groups = {"UBF8T346G9.Office"}},
	{bundleId = "com.apple.podcasts", name = "Podcasts", groups = {"243LU875E5.groups.com.apple.podcasts"}},
	{bundleId = "ru.keepcoder.Telegram", name = "Telegram", team = "6N38VWS5BX", groups = {"6N38VWS5BX.ru.keepcoder.Telegram"}},
	{bundleId = "com.tinyspeck.slackmacgap", name = "Slack"},
	{bundleId = "com.apple.mail", name = "Mail"},
}
local index = Leftovers.index(apps)

-- mdls prints identifier and display name for each bundle in turn.
local parsed = Leftovers.parseApplications("com.apple.mail\0Mail\0(null)\0(null)\0com.x.Tool\0(null)", {"/A/Mail.app", "/B/Odd.app", "/C/Tool.app"})
t.assertEqual(#parsed, 2, "bundles without an identifier are left out")
t.assertEqual(parsed[1].name, "Mail", "the display name names the app")
t.assertEqual(parsed[2].name, "Tool", "a missing display name falls back to the bundle's file name")

-- Ownership by app group, identifier and team.
local function owner(name, byName) local names, how = Leftovers.owner(name, index, byName); return names and table.concat(names, ", "), how end
t.assertEqual(table.pack(owner("UBF8T346G9.Office"))[2], "group", "an app group an app declares names its apps")
t.assertEqual(owner("UBF8T346G9.Office"), "Microsoft Word, Microsoft Excel", "every app declaring the group owns it")
t.assertEqual(owner("243LU875E5.groups.com.apple.podcasts"), "Podcasts", "a digit-led team group is matched exactly")
t.assertEqual(owner("com.tinyspeck.slackmacgap.ShipIt"), "Slack", "a helper's folder belongs to its app")
t.assertEqual(owner("com.microsoft.Word.plist"), "Microsoft Word", "a preferences file names its app")
t.assertEqual(table.pack(owner("UBF8T346G9.OneDriveSync"))[2], "team", "an undeclared group of a known team names the developer's apps")
t.assertEqual(owner("com.removed.App"), nil, "an uninstalled app's folder has no owner")
t.assertEqual(owner("Slack", true), "Slack", "Application Support folders may be named after their app")
t.assertEqual(Leftovers.owner("x", nil), nil, "no installed apps, no owner")
t.assertEqual(Leftovers.classify("UBF8T346G9.Office", false, index), nil, "a declared group is never a leftover")
t.assertEqual(Leftovers.classify("2DC432GLL2.com.removed.Thing", false, Leftovers.index({{bundleId = "com.other.App", team = "2DC432GLL2", name = "Other"}})), "medium",
	"a group of an installed developer is only a possible leftover")

-- Explanations.
local home = "/Users/me"
local function explain(path, extra)
	local facts = {home = home, apps = index}
	for key, value in pairs(extra or {}) do facts[key] = value end
	return Explain.path(path, facts)
end
local bird = explain(home .. "/Library/Caches/com.apple.bird")
t.assertEqual(bird.owner, "iCloud Drive", "an exact location names its owner")
t.expect(bird.what:find("iCloud Drive", 1, true) ~= nil, "and says what it is")
local cloudkit = explain(home .. "/Library/Caches/com.apple.cloudd")
t.assertEqual(cloudkit.owner, "iCloud", "an Apple service is named by the feature people know")
t.assertEqual(cloudkit.kind, "Cache", "the parent says what kind of data it is")
t.assertEqual(explain(home .. "/Library/Caches/com.apple.mail").owner, "Mail", "an Apple app resolves like any installed app")
t.assertEqual(explain(home .. "/Library/Caches/com.apple.somethingnew").owner, "macOS", "an unknown Apple folder is macOS's, never unclaimed")
local slack = explain(home .. "/Library/Containers/com.tinyspeck.slackmacgap")
t.assertEqual(slack.owner, "Slack", "a container names its app")
t.expect(slack.what:find("Slack's sandbox", 1, true) ~= nil and not slack.what:find("%s", 1, true), "the owner fills the sentence")
local office = explain(home .. "/Library/Group Containers/UBF8T346G9.Office")
t.assertEqual(office.owner, "Microsoft Word and Microsoft Excel", "a shared container names the apps sharing it")
local removed = explain(home .. "/Library/Application Support/com.removed.App")
t.expect(removed.unclaimed and removed.owner == nil and removed.what ~= nil, "a folder no installed app claims says so")
local plain = explain(home .. "/Library/Caches/vscode-cpptools")
t.expect(plain.kind == "Cache" and not plain.unclaimed and plain.owner == nil, "a plain name nobody claims is not called unclaimed")
t.assertEqual(explain(home .. "/Library/Caches/Slack").owner, "Slack", "a cache named after its app names it")
t.assertEqual(explain(home .. "/Library/Caches/GeoServices").owner, "Maps", "a cache named after an Apple service names its feature")
local waiting = Explain.path(home .. "/Library/Application Support/com.removed.App", {home = home})
t.expect(waiting and not waiting.unclaimed and waiting.what == nil, "before Spotlight answers nothing is called unclaimed")
local inner = explain(home .. "/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches/com.tinyspeck.slackmacgap")
t.assertEqual(inner.kind, "Cache", "a sandbox's own Library mirrors ~/Library")
t.assertEqual(inner.owner, "Slack", "and its items belong to the sandbox's app")
t.assertEqual(explain(home .. "/Library/Containers/com.tinyspeck.slackmacgap/Data/Documents").owner, "Slack", "anything else in a sandbox is its app's")
local uuid = "0928563D-373E-4693-B6C6-F7D41B0B6B8B"
local asked
local byMetadata = explain(home .. "/Library/Containers/" .. uuid, {container = function(path) asked = path; return "com.tinyspeck.slackmacgap" end})
t.assertEqual(asked, home .. "/Library/Containers/" .. uuid, "a container named by a UUID reads its metadata")
t.assertEqual(byMetadata.owner, "Slack", "and the metadata names its app")
t.expect(explain(home .. "/Library/Containers/" .. uuid).unclaimed, "without the metadata it is unclaimed")
local asset = explain("/System/Library/AssetsV2/com_apple_MobileAsset_Brand_New")
t.assertEqual(asset.owner, "macOS", "a downloaded asset the map does not name is macOS's")
t.expect(asset.what:find("for Brand New", 1, true) and asset.what:find("System Integrity Protection", 1, true), "it names its asset type and why it stays")
t.assertEqual(explain("/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels").kind, "Apple Intelligence language model", "the map names the assets it knows")
local precache = explain("/Library/Application Support/precache")
t.expect(precache.what:find("Not part of macOS", 1, true) == 1, "a folder named precache is explained wherever it is")
t.expect(explain("/Library/LaunchDaemons/com.removed.helper.plist").unclaimed, "a startup daemon of removed software is unclaimed")
t.assertEqual(explain("/Users/me/Documents/report.pdf"), nil, "an ordinary file has no explanation")
t.assertEqual(Explain.names({"A", "B", "C", "D"}), "A, B and 2 more", "long owner lists are shortened")
t.assertEqual(Explain.package(Explain.packages("volume: /\npkgid: com.x.pkg\npkg-version: 1\n")), "Installed by the package com.x.pkg.", "a receipt names its package")
t.assertEqual(Explain.package({}), nil, "no receipt, no package")

-- Knowledge integrity: every rule fills its owner and every service is named.
for parent, rule in pairs(Library.parents) do
	t.expect(rule.kind and rule.what and rule.unknown and rule.what:find("%s", 1, true), "rule " .. parent .. " is complete")
	t.expect(Map.find(parent) or parent:match("^~/Library/") or parent:match("^/Library/") or parent:match("^/System/"), "rule " .. parent .. " names a Library folder")
end
for name, entry in pairs(Library.names) do
	t.expect(name == name:lower() and entry.kind and entry.what, "name " .. name .. " is lowercase and explained")
end
for _, area in ipairs(Map.areas) do
	for _, location in ipairs(area.locations) do
		t.expect(location.owner == nil or (type(location.owner) == "string" and location.owner ~= ""), "owner of " .. location.path)
	end
end

-- Search answers the questions people ask by name.
local GuideHelper = require("apps.diskmap.helpers.Guide")
local FilesystemHelper = require("apps.diskmap.helpers.Filesystem")
local function topics(needle) local ids = {}; for _, row in ipairs(GuideHelper.search(needle)) do ids[row.id] = true end; return ids end
local function places(needle) local ids = {}; for _, row in ipairs(FilesystemHelper.search(needle)) do ids[row.path] = true end; return ids end
t.expect(topics("precache").precache, "“precache” finds the staged updates topic")
t.expect(places("precache")["/Library/Application Support/Apple/AssetCache/Data"], "and Content Caching on the macOS Folders page")
t.expect(places("com.apple.bird")["~/Library/Caches/com.apple.bird"], "a folder name finds its location")
t.expect(topics("com.apple")["apple-folders"], "“com.apple” finds whether Apple folders may go")
t.expect(topics("launchagents")["login-items"] or topics("launch")["login-items"], "login agents are explained")
t.expect(topics("corespotlight")["core-spotlight"] and topics("mediaanalysisd")["photo-analysis"], "runaway Apple caches are explained")

-- The Folder page: every row says whose it is, the line under the map what it is.
local service = Mock.new()
local mockHome = service.home
for _, item in ipairs({
	{mockHome .. "/Library/Caches/com.apple.bird/a.bin", 400e6},
	{mockHome .. "/Library/Caches/com.tinyspeck.slackmacgap/b.bin", 300e6},
	{mockHome .. "/Library/Caches/com.removed.App/c.bin", 200e6},
	{"/Library/Application Support/Vendor/d.bin", 100e6},
}) do table.insert(service.items, {path = item[1], allocatedBytes = item[2], countedBytes = item[2], used = os.time()}) end
local installed = {{bundleId = "com.tinyspeck.slackmacgap", name = "Slack"}}
service.installedApplications = function(done) done(installed) end
service.packageOwner = function(path, done) done(path:find("Vendor", 1, true) and {"com.vendor.pkg"} or {}) end
local app = Controller.new(service)
app:createWindow()
app:show("folder")
local page = app.env:page("folder")
page:open(mockHome .. "/Library/Caches")
page:data()
t.assertEqual(Model.db.installedApplications, installed, "opening a folder asks which apps are installed")
local subtitles = {}
for _, row in ipairs(page.rows) do subtitles[row.name] = row.subtitle end
t.expect(subtitles["com.apple.bird"]:find("^iCloud Drive · ") ~= nil, "an Apple service's row names its feature")
t.expect(subtitles["com.tinyspeck.slackmacgap"]:find("^Slack · ") ~= nil, "an app's cache names the app")
t.expect(subtitles["com.removed.App"]:find("^No installed app · ") ~= nil, "an unclaimed cache says so")
t.expect(page:selection().detail:find("^Caches: ") ~= nil, "with nothing selected the line explains the open folder")
page.selected = mockHome .. "/Library/Caches/com.tinyspeck.slackmacgap"
local detail = page:selection().detail
t.expect(detail:find("Slack's cache", 1, true) ~= nil, "a selected folder is explained under its name and size")
page:open("/Library/Application Support")
page:data()
local vendor = "/Library/Application Support/Vendor"
page:selectRow(nil, nil, {id = vendor, path = vendor})
t.expect(page:selection().detail:find("Installed by the package com.vendor.pkg.", 1, true) ~= nil, "an installer receipt names a shared folder's package")
local calls = 0
service.packageOwner = function(_, done) calls = calls + 1; done({}) end
page:selectRow(nil, nil, {id = vendor, path = vendor})
t.assertEqual(calls, 0, "a receipt is asked for once per item")

os.exit(t.summary() and 0 or 1)
