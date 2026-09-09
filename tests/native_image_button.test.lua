_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local button = ns.Button { title = "", style = "plain", accessibilityLabel = "Open adventure" }
t.assertEqual(button.bordered, false, "plain action uses borderless native button")
t.assertEqual(button.accessibilityLabel, "Open adventure", "image action has accessible label")
t.assertEqual(#button.subviews, 0, "plain action does not render an opaque compound card")
local image = ns.Image { path = "examples/adventure-arena/assets/planetfall.jpg", contentMode = "fill" }
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

os.exit(t.summary() and 0 or 1)
