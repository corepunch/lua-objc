-- The manifest app: sidebar, Go menu and page set from one file, the model
-- graph as the bootstrap, and --page / --isolated for every app.
_G.__headless = true
local t = require("TestKit")
local ns = require("ns")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local App = require("data.app")
local Manifest = require("data.manifest")

local MANIFEST = "demo/storage/app.xml"

-- The manifest.
local manifest = Manifest.parse(xml.parse(xml.source(MANIFEST)))
t.assertEqual(manifest.name, "Storage", "the app's name")
t.assertEqual(#manifest.order, 2, "two pages")
t.assertEqual(manifest.startup, "folders", "the startup page")
t.assertEqual(manifest.sections[1].title, "Storage", "a section groups pages")
t.assertEqual(manifest.pages.settings.model, "settings", "a page names its model")

local function parse(source) return Manifest.parse(xml.parse(source)) end
local function rejects(source, pattern, message)
	local ok, err = pcall(parse, source)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end
local page = '<Page id="a" title="A" view="V" model="m" />'
rejects('<Window />', "must be <App>", "the root is App")
rejects('<App><Model id="m" class="M" />' .. page .. page .. '</App>', "declared twice", "a page id is unique")
rejects('<App>' .. page .. '</App>', "does not declare", "a page's model must be declared")
rejects('<App><Model id="m" class="M" /><Page id="a" title="A" model="m" /></App>', "needs view", "a page needs a view")
rejects('<App startup="zz"><Model id="m" class="M" />' .. page .. '</App>', "startup page zz", "the startup page exists")
rejects('<App><Model id="m" class="M" /><Page id="a" title="A" view="V" model="m" key="1" /><Page id="b" title="B" view="V" model="m" key="1" /></App>',
	"share the key 1", "keys are unique")
rejects('<App><Model id="m" class="M" /><Menu /></App>', "not part of the manifest", "only manifest tags")
-- A page may be code-behind only, carry its own attributes and stay out of the sidebar.
local custom = parse('<App><Page id="a" title="A" controller="AController" workflow="dev" sidebar="Short" />' ..
	'<Page id="b" title="B" controller="BController" listed="false" /></App>')
t.assertEqual(custom.pages.a.attrs.workflow, "dev", "other attributes are kept")
t.assertEqual(#custom.sections[1].pages, 1, "an unlisted page is not in its section")
t.assertEqual(custom.pages.b.listed, false, "but it is a page")
t.assertEqual(#custom.order, 2, "and in the page order")
rejects('<App><Page id="a" title="A" /></App>', "view and model, or a controller", "a page without a controller needs a view and a model")
t.assertEqual(Manifest.options({ "--page=settings", "--isolated", "x" }).page, "settings", "--page")
t.assertEqual(Manifest.options({ "--isolated" }).isolated, true, "--isolated")
t.assertEqual(Manifest.options({}).page, nil, "no options")

-- A window from the manifest.
local app = App.launcher(MANIFEST).new({ args = {} })
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
t.expect(app.graph:get("folders") ~= nil and app.graph:get("settings") ~= nil, "the folders page builds settings, which it needs")

-- The folders page binds without a controller.
local function find(root, id)
	if root.accessibilityIdentifier == id then return root end
	for _, child in ipairs(root.subviews or {}) do
		local found = find(child, id)
		if found then return found end
	end
end
t.assertEqual(#app.graph:get("folders"):rows(), 6, "the model has six folders")
t.assertEqual(app.refs.folders ~= nil, true, "the list is a ref")
bridge._appkitLayout(window)

-- A changed setting makes the folders stale and the page rebinds.
local folders, settings = app.graph:get("folders"), app.graph:get("settings")
settings.threshold = 2
app.graph:changed("settings")
t.assertEqual(#folders:rows(), 5, "a larger threshold hides small folders (states stay)")

-- Switching pages disposes the old one and builds the new one.
app:show("settings")
t.assertEqual(app.current, "settings", "show switches pages")
t.assertEqual(app.page.binder.model, settings, "the settings page binds the settings model")
t.assertEqual(app.sidebar.documentView.selectedRow, 2, "the sidebar follows")
app:show("folders")
t.assertEqual(app.current, "folders", "and back")

-- A model's activate/deactivate run when its page mounts and is disposed.
local log = {}
folders.activate = function() table.insert(log, "activate") end
folders.deactivate = function() table.insert(log, "deactivate") end
app:show("settings")
app:show("folders")
t.assertEqual(table.concat(log, ","), "deactivate,activate", "leaving a page deactivates its model; mounting activates it")
app:show("settings")
t.assertEqual(table.concat(log, ","), "deactivate,activate,deactivate", "and again on dispose")
folders.activate, folders.deactivate = nil, nil

-- --page and --isolated.
local only = App.launcher(MANIFEST).new({ args = { "--page=settings", "--isolated" } })
only:createWindow()
t.assertEqual(only.current, "settings", "--page starts on that page")
t.expect(only.sidebar == nil, "--isolated shows the page alone")
t.expect(only.graph:get("settings") ~= nil, "the page's model is built")
t.expect(only.graph:get("folders") == nil, "and only the models the page needs")
local viaPage = App.launcher(MANIFEST).new({ args = { "--page=settings" } })
viaPage:createWindow()
t.assertEqual(viaPage.current, "settings", "--page without --isolated keeps the shell")
t.expect(viaPage.sidebar ~= nil, "with its sidebar")
local ok, err = pcall(function() App.launcher(MANIFEST).new({ args = { "--page=nope" } }) end)
t.expect(not ok and tostring(err):find("no such page"), "an unknown page is an error")

os.exit(t.summary() and 0 or 1)
