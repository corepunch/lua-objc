_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local first = ns.VStack { ns.Text "Root" }
local navigation = ns.NavigationStack { content = first, title = "Adventures" }
navigation.frameSize = ns.Size(640, 720)
navigation:layout(640)
t.assertEqual(navigation.depth, 1, "navigation begins with one page")
t.assertEqual(navigation.currentController.title, "Adventures", "root title belongs to native controller")
t.assertSize(first, 640, 720, "native page receives navigation viewport")
local label = ns.Text "Detail"
local detail = ns.VStack { label }
navigation:push(ns.HostingController(detail), "Game")
t.assertEqual(navigation.depth, 2, "push appends native page")
t.assertEqual(navigation.currentController.title, "Game", "push selects destination")
t.assertSize(detail, 640, 720, "destination fills same navigation container")
label.text = "Edited detail"
navigation.frameSize = ns.Size(420, 360)
navigation:layout(420)
t.assertSize(detail, 420, 360, "native page resizes with container")
t.assertEqual(label.text, "Edited detail", "resize retains page state")
navigation:pop()
t.assertEqual(navigation.depth, 1, "pop removes destination")
t.assertEqual(navigation.currentController.title, "Adventures", "pop returns to retained root")
t.assertSize(first, 420, 360, "returning root receives current viewport")
navigation:pop()
t.assertEqual(navigation.depth, 1, "pop at root is harmless")
os.exit(t.summary() and 0 or 1)
