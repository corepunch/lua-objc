-- The manifest app: sidebar, Go menu and page set from one file, pages built
-- from routes over models of a bound store, and --page / --isolated for every app.
_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local App = require("data.app")
local Manifest = require("data.manifest")
local Model = require("data.model")

local MANIFEST = "demo/storage/app.xml"
-- The demo's launch class: the manifest with the store it seeds.
local Storage = dofile("demo/storage/init.lua")

-- The manifest.
local manifest = Manifest.parse(xml.parse(xml.source(MANIFEST)))
t.assertEqual(manifest.name, "Storage", "the app's name")
t.assertEqual(#manifest.order, 2, "two pages")
t.assertEqual(manifest.startup, "folders", "the startup page")
t.assertEqual(manifest.sections[1].title, "Storage", "a section groups pages")
t.assertEqual(manifest.pages.settings.route, "settings", "a page's route is its id when it names none")
t.assertEqual(manifest.routes, "routes", "the app's routes are the routes module beside app.xml")

local function parse(source) return Manifest.parse(xml.parse(source)) end
local function rejects(source, pattern, message)
	local ok, err = pcall(parse, source)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end
local page = '<Page id="a" title="A" />'
rejects('<Window />', "must be <App>", "the root is App")
rejects('<App>' .. page .. page .. '</App>', "declared twice", "a page id is unique")
rejects('<App><Page id="a" /></App>', "needs title", "a page needs a title")
rejects('<App startup="zz">' .. page .. '</App>', "startup page zz", "the startup page exists")
rejects('<App><Page id="a" title="A" key="1" /><Page id="b" title="B" key="1" /></App>',
	"share the key 1", "keys are unique")
rejects('<App><Model id="m" class="M" /></App>', "not part of the manifest", "models are not declared in the manifest")
-- A page may name a route with arguments, and stay out of the sidebar.
local custom = parse('<App routes="pages"><Page id="a" title="A" route="work" workflow="dev" sidebar="Short" />' ..
	'<Page id="b" title="B" route="work" listed="false" /></App>')
t.assertEqual(custom.routes, "pages", "the manifest names the routes module")
t.assertEqual(custom.pages.a.route, "work", "a page names its route")
t.assertEqual(custom.pages.a.attrs.workflow, "dev", "other attributes are kept as the route's params")
t.assertEqual(#custom.sections[1].pages, 1, "an unlisted page is not in its section")
t.assertEqual(custom.pages.b.listed, false, "but it is a page")
t.assertEqual(#custom.order, 2, "and in the page order")
t.assertEqual(Manifest.options({ "--page=settings", "--isolated", "x" }).page, "settings", "--page")
t.assertEqual(Manifest.options({ "--isolated" }).isolated, true, "--isolated")
t.assertEqual(Manifest.options({}).page, nil, "no options")

-- A window from the manifest.
local app = Storage.new({ args = {} })
local window = app:createWindow()
t.expect(window ~= nil, "the manifest builds a window")
t.assertEqual(app.current, "folders", "the startup page is shown")
local rows = app:rows()
t.assertEqual(#rows, 3, "a header and two pages")
t.assertEqual(rows[1].title, "Storage", "the section header")
t.assertEqual(rows[3].name, "Settings", "the sidebar lists the manifest's pages")
t.assertEqual(app.sidebar.documentView.selectedRow, 1, "the current page is selected")
local actions = app:actions()
t.expect(actions.page_settings and actions.isPage_folders, "the Go menu has an action and a validator per page")
t.assertEqual(select(2, actions.isPage_folders()), true, "the current page is checked")
t.expect(app.pages.folders ~= nil and app.pages.settings == nil, "showing a page builds that page alone")

-- The folders page is a view over its models' data, with no controller.
local Folders = require("demo.storage.models.Folders")
local Settings = require("demo.storage.models.Settings")
t.expect(Model.db == app.store, "launching binds the app's store")
t.assertEqual(#Folders:all(), 6, "the model has six folders")
t.assertEqual(app.refs.folders ~= nil, true, "the list is a ref")
bridge._appkitLayout(window)
t.assertEqual(app.refs.folders.rowCount, 6, "the page shows every folder")

-- An action is a method of the page followed by the same request again.
local folders = app.pages.folders
Settings:current().threshold = 2
app.page:update()
t.assertEqual(app.refs.folders.rowCount, 5, "a larger threshold hides small folders (unmeasured ones stay)")
app.page.actions.rescan()
t.assertEqual(folders.scans, 1, "an action runs the page's method")
t.assertEqual(select(2, Settings:current():update({deviceName = "  "})), "A device needs a name.", "a constraint refuses an empty name")

-- Switching pages disposes the old one and builds the new one.
app:show("settings")
t.assertEqual(app.current, "settings", "show switches pages")
t.assertEqual(app.page.request, app.pages.settings, "the settings page is drawn from the settings route")
t.assertEqual(app.pages.settings.view, "Settings", "which names its view")
t.assertEqual(app.sidebar.documentView.selectedRow, 2, "the sidebar follows")
-- A refused action draws its message; the next draw clears it.
local result, message = app.page.actions.setDeviceName(" ")
t.expect(result == nil and message == "A device needs a name.", "a refused action returns its message")
t.assertEqual(app.refs.error and app.refs.error.text, "A device needs a name.", "and the page shows it")
t.assertEqual(Settings:current().deviceName, "My Mac", "the name is unchanged")
app.page.actions.setDeviceName("Studio")
t.expect(app.refs.error == nil and Settings:current().deviceName == "Studio", "an accepted change clears the message")
app.page.actions.setThreshold(1)
t.assertEqual(Settings:current().threshold, 1, "the picker's index is the threshold")
Settings:current():update({threshold = 0})
app:show("folders")
t.assertEqual(app.current, "folders", "and back")

-- A page's activate/deactivate run when it mounts and is disposed.
local log = {}
folders.activate = function() table.insert(log, "activate") end
folders.deactivate = function() table.insert(log, "deactivate") end
app:show("settings")
app:show("folders")
t.assertEqual(table.concat(log, ","), "deactivate,activate", "leaving a page deactivates it; mounting activates it")
app:show("settings")
t.assertEqual(table.concat(log, ","), "deactivate,activate,deactivate", "and again on dispose")
folders.activate, folders.deactivate = nil, nil

-- --page and --isolated.
local only = Storage.new({ args = { "--page=settings", "--isolated" } })
only:createWindow()
t.assertEqual(only.current, "settings", "--page starts on that page")
t.expect(only.sidebar == nil, "--isolated shows the page alone")
t.expect(only.pages.settings ~= nil and only.pages.folders == nil, "only the shown page is built")
t.expect(Model.db == only.store and only.store ~= app.store, "each launch binds a fresh store from the seed")
local viaPage = Storage.new({ args = { "--page=settings" } })
viaPage:createWindow()
t.assertEqual(viaPage.current, "settings", "--page without --isolated keeps the shell")
t.expect(viaPage.sidebar ~= nil, "with its sidebar")
local ok, err = pcall(function() Storage.new({ args = { "--page=nope" } }) end)
t.expect(not ok and tostring(err):find("no such page"), "an unknown page is an error")

-- One route serves several pages, which differ by their params.
local Routes = require("data.routes")
local work = {view = "V", data = function(self) return {workflow = self.params.workflow} end}
local music = Routes.page(Routes.find({work = work}, custom.pages.a), custom.pages.a, {name = "services"})
t.assertEqual(music:data({}).workflow, "dev", "a page reads its manifest attributes as params")
t.assertEqual(music.app.name, "services", "and the app's services as self.app")
t.assertEqual(music.id, "a", "and knows its id")
ok, err = pcall(Routes.find, {}, custom.pages.a)
t.expect(not ok and tostring(err):find("names the route work"), "a page whose route is missing is an error")
local counting = {view = "V", data = function() return {} end, init = function(self) self.choices = {} end}
local one, two = Routes.page(counting, custom.pages.a, {}), Routes.page(counting, custom.pages.b, {})
t.expect(one.choices and one.choices ~= two.choices, "init gives each page its own tables")
ok, err = pcall(Routes.find, {work = {}}, custom.pages.a)
t.expect(not ok and tostring(err):find("needs a view"), "a route names its view")

-- An app's optional modules: absent is nil, a broken one is an error.
t.assertEqual(App.optional("demo.storage.NoSuchModule"), nil, "an absent optional module is nil")
package.preload["test.broken"] = function() error("broken inside") end
local brokenOk, brokenErr = pcall(App.optional, "test.broken")
t.expect(not brokenOk and tostring(brokenErr):find("broken inside", 1, true), "an error inside an optional module is raised")

os.exit(t.summary() and 0 or 1)
