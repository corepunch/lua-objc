-- The SDK sheet binds to its model by name: rows, status line and the
-- search field are bound, and the controller only starts discovery.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local Sheet = require("apps.diskmap.Sheet")
local Schema = require("data.schema")
local Controller = require("apps.diskmap.controllers.SdksController")
local SdkList = require("apps.diskmap.models.SdkList")

-- The model satisfies its schema.
local schemas = Schema.app("apps/diskmap/schemas")
local list = SdkList.new()
t.assertEqual(#schemas("SdkList"):problems(list), 0, "SdkList satisfies its schema")
t.assertEqual(list:status(), "Reading SDK folders…", "nothing discovered yet")

-- The sheet needs no window: present just renders the view.
local present = Sheet.present
Sheet.present = function(render) local _, refs = render(); return {}, refs end
local dismissed
local dismiss = ns.dismiss
ns.dismiss = function() dismissed = true end
local searchProps
local searchField = ns.SearchField
ns.SearchField = function(props) searchProps = props; return searchField(props) end

local sizes
local service = {
	bundles = function()
		return {
			{path = "/x/MacOSX.sdk", name = "MacOSX15.sdk", bytes = 2000000000},
			{path = "/x/iPhoneOS.sdk", name = "iPhoneOS18.sdk", bytes = nil},
		}
	end,
	measure = function(paths, done) sizes = done; t.assertEqual(#paths, 1, "only the unmeasured SDK is measured") end,
}
local controller = Controller.new({}, service)
controller:open({}, {name = "Xcode", path = "/Applications/Xcode.app"})
local binder = controller.binder
t.assertEqual(#binder.record.rows, 2, "both SDKs are bound")
t.assertEqual(binder.record.rows[1].name, "MacOSX15.sdk", "the largest leads")
t.assertEqual(binder.record.rows[1].size, bridge._formatBytes(2000000000), "sizes use the system formatter")
t.assertEqual(binder.record.rows[2].size, "Not measured", "an unmeasured size says so")
t.assertEqual(controller.refs.status.text, "Measuring SDKs…", "the status line is bound")

sizes({1000000})
t.assertEqual(controller.refs.status.text, "2 SDKs", "measuring finished")
t.assertEqual(binder.record.rows[2].size, bridge._formatBytes(1000000), "the measured size appears")

-- Search is a two-way text binding; the setter filters.
searchProps.onChange("iphone")
t.assertEqual(#binder.record.rows, 1, "search filters through the model")
t.assertEqual(controller.refs.status.text, "1 SDK", "the status line follows")
searchProps.onChange("nothing")
t.assertEqual(controller.refs.status.text, "No matching SDKs.", "an empty result says so")

controller:close()
t.assertEqual(dismissed, true, "closing dismisses the sheet")
t.expect(controller.binder == nil, "and releases the binding")

Sheet.present, ns.dismiss, ns.SearchField = present, dismiss, searchField
os.exit(t.summary() and 0 or 1)
