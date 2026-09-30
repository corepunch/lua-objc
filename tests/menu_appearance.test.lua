_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local chosen = nil

local items = { { title = "Look Around", action = function() chosen = "look" end }, { title = "Inventory", action = function() chosen = "inventory" end } }
local menu = ns.Menu { title = "", systemImage = "plus", style = "glass", width = 52, height = 52, accessibilityLabel = "More commands", items = items }
t.assertEqual(menu.bezelStyle, 7, "a symbol glass menu uses the native circular bezel")
local button = menu
t.assertEqual(button.cell.arrowPosition, 0, "an image-only menu omits the disclosure arrow")
t.assertEqual(button.imagePosition, 1, "the menu centers its symbol alone")
t.assertEqual(button.accessibilityLabel, "More commands", "the native menu retains its accessible label")
t.assertEqual(button.menu.numberOfItems, 3, "the native menu retains its label and commands")
button:selectIndex(1)
bridge._invokeAction(button)
t.assertEqual(chosen, "look", "the menu dispatches its selected command")
local plain = ns.Menu { title = "", systemImage = "plus", items = items }
t.assertEqual(plain.cell.arrowPosition, 0, "plain symbol menus also omit the arrow")
local labelled = ns.Menu { title = "Commands", style = "glass", height = 32, items = items }
t.assertEqual(labelled.bezelStyle, 1, "labelled glass menus use the native rounded bezel")
t.expect(labelled.cell.arrowPosition ~= 0, "labelled menus keep their disclosure arrow")
os.exit(t.summary() and 0 or 1)
