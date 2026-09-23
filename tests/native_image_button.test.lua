_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local button = ns.Button { title = "", style = "plain", accessibilityLabel = "Open adventure" }
t.assertEqual(button.bordered, false, "plain action uses borderless native button")
t.assertEqual(button.accessibilityLabel, "Open adventure", "image action has accessible label")
t.assertEqual(#button.subviews, 0, "plain action does not render an opaque compound card")
local image = ns.Image { path = "apps/adventure-arena/assets/planetfall.jpg", contentMode = "fill" }
local source = image.sourceImage.size
image.frameSize = ns.Size(300, 100)
t.expect(image.image.size.width >= 300 and image.image.size.height >= 100, "aspect fill covers viewport")
t.expect(math.abs(image.image.size.width / image.image.size.height - source.width / source.height) < 0.001, "fill preserves source aspect ratio")
image.frameSize = ns.Size(100, 300)
t.expect(image.image.size.width >= 100 and image.image.size.height >= 300, "fill follows portrait resize")
image.contentModeName = "fit"
t.assertEqual(image.image.size.width, source.width, "fit restores original source dimensions")
t.assertEqual(image.image.size.height, source.height, "resize never compounds source scaling")
local label = ns.Text { "4.7 · Play", size = 13, weight = "bold" }
local row = ns.HStack { label }
row.frameSize = ns.Size(200, 50)
row:layout(200)
t.expect(label.cell.usesSingleLineMode, "unwrapped label uses native single-line drawing without cell wrapping")
row.frameSize = ns.Size(30, 100)
row:layout(30)
t.expect(not label.cell.usesSingleLineMode, "constrained label restores native multiline drawing")
row.frameSize = ns.Size(200, 50)
row:layout(200)
t.expect(label.cell.usesSingleLineMode, "widening restores native drawing mode")

local xml = require("ui.xml")
local path, pathRefs = xml.render('<VStack><Label ref="label" text="/Users/example/Library/Developer/CoreSimulator/Devices" size="11" maxWidth="infinity" lines="0" wrapping="character" /></VStack>', {}, ns)
path.frameSize = ns.Size(200, 100); path:layout(200)
t.assertEqual(pathRefs.label.lineBreakMode, 1, "character wrapping reaches the native text cell")
t.expect(pathRefs.label.size.height >= 26, "unbroken paths wrap instead of losing their final characters")
path.frameSize = ns.Size(900, 100); path:layout(900)
pathRefs.label.text = "/Users/igor/Library/Developer/CoreSimulator/Devices\n10.8 GB · complete"
path.frameSize = ns.Size(275, 100); path:layout(275)
t.assertEqual(pathRefs.label.lineBreakMode, 1, "text mutation retains declared character wrapping after a wide layout")
t.assertEqual(pathRefs.label.size.height, 39, "path and evidence occupy all three lines after narrowing")
local text = ns.Text { "Review in Xcode. Keep resources required by your projects and devices. Archives can contain irreplaceable release builds and debug symbols.", size = 12, fillWidth = true }
local paragraph = ns.VStack { text }
paragraph.frameSize = ns.Size(275, 200); paragraph:layout(275)
t.expect(text.size.height >= 60, "wrapped paragraph includes native field insets before counting lines")
paragraph.frameSize = ns.Size(900, 200); paragraph:layout(900)
t.expect(text.size.height < 60, "widening releases the extra wrapped lines")

os.exit(t.summary() and 0 or 1)
