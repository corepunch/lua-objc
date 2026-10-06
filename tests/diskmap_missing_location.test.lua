_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Model = require("data.model")
local Store = require("apps.diskmap.Store")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- A location that is not on this Mac (JetBrains never installed) was listed
-- on the Map as "0 KB", and Inspect Folder Contents measured a folder that
-- does not exist. The scan reports it missing; the Map leaves it out.
local model = Store.new("/Users/test")
Model.bind(model)
Scans:apply({"jetbrains", "vscode-extensions"}, {trees = {false, {kb = 2.6e6}}, rootStates = {"missing", "complete"}})
t.expect(model.measurements.jetbrains.missing, "the scan records the location as missing")
t.assertEqual(model.measurements.jetbrains.bytes, 0, "and as taking no space")
local names = {}
for _, row in ipairs(Categories:rows("editors")) do table.insert(names, row.id) end
t.expect(not table.concat(names, ","):find("jetbrains", 1, true), "Editors & IDEs does not list a missing location")
t.expect(table.concat(names, ","):find("vscode-extensions", 1, true), "and still lists what is there")

-- While a folder is measured, its spinner and progress sit in the middle of
-- the page, not at its leading edge.
local service = Mock.new({showcase = true})
service.scanFolder = function() return {} end
local app = Controller.new(service)
local window = app:createWindow()
app:show("folder", {path = "/Users/appleseed/Downloads"})
local refs = app.page.refs
for _ = 1, 2 do refs.page.size = ns.Size(900, 600); refs.page:layout(900) end
local function centre(view) local f = view.frameInWindow; return f.origin.x + f.size.width / 2 end
t.expect(refs.folderScanning ~= nil, "the folder is being measured")
t.assertEqual(refs.folderScanning.frame.size.width, refs.folderScanning.superview.frame.size.width, "the measuring view spans the page")
t.assertEqual(centre(refs.folderSpinner), centre(refs.folderScanning), "its spinner is centred")
t.assertEqual(centre(refs.folderProgress), centre(refs.folderScanning), "and so is its progress")
window:close()

os.exit(t.summary() and 0 or 1)
