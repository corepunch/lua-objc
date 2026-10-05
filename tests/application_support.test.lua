_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")

local support = ns.applicationSupportDirectory("lua-objc")
t.expect(support and support:sub(-#"/Library/Application Support/lua-objc") == "/Library/Application Support/lua-objc", "the app's folder is inside Application Support")
t.expect(not pcall(ns.applicationSupportDirectory, "../escape"), "a folder name cannot leave Application Support")
t.expect(not pcall(ns.applicationSupportDirectory, ""), "an empty folder name is refused")
os.exit(t.summary() and 0 or 1)
