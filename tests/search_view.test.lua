_G.__headless = true

local bridge = require("bridge")
local SearchView = require("examples.ide.components.search_view")
local ns = require("AppKit")
local t = require("TestKit")

local function dimensions(view)
	local size = view.size
	return size.width, size.height
end

local selectedPath = nil
local search = SearchView {
	files = {
		"/tmp/test/main.lua",
		"/tmp/test/App.lua",
		"/tmp/test/utils.lua",
	},
	onSelect = function(path)
		selectedPath = path
	end,
}
t.expect(search ~= nil, "SearchView creates without error")

local width, height = dimensions(search._panel)
t.assertEqual(width, 520, "SearchView uses the palette width")
t.assertEqual(height, 48, "SearchView starts as only the input bar")
t.assertEqual(search:resultCount(), 0, "empty query has no results")
t.expect(not search:isExpanded(), "empty SearchView is collapsed")
t.assertEqual(search._resultsView.rowCount, 0,
	"empty datasource starts with zero rows")
t.assertEqual(search._searchField.accessibilityLabel, "Open Quickly",
	"SearchView input has a native accessibility label")
t.assertEqual(search._searchField.placeholderString, "Open Quickly",
	"SearchView uses Xcode's concise placeholder")
t.assertEqual(search._searchIcon.accessibilityLabel, "Search",
	"SearchView has an accessible native search symbol")
local iconWidth, iconHeight = dimensions(search._searchIcon)
t.assertEqual(iconWidth, 28, "search symbol has a stable alignment frame")
t.assertEqual(iconHeight, 28, "search symbol frame is vertically centered")
local headerWidth, headerHeight = dimensions(search._searchHeader)
t.assertEqual(headerWidth, 520, "search header fills the palette")
t.assertEqual(headerHeight, 48, "search header owns the collapsed height")
local panelStyle = bridge._panelStyleState(search._panel)
t.expect(panelStyle.usesNativeShadow,
	"SearchView delegates its shadow entirely to NSPanel")
t.expect(panelStyle.usesNativeFrame,
	"SearchView uses AppKit's titled full-size panel frame")
t.assertEqual(#search._files, 3, "SearchView retains explicitly supplied files")

-- Simulate native user input. The generic NSTextField callback performs all
-- filtering and replaces the NSOutlineView datasource atomically from Lua.
bridge._textFieldTestInput(search._searchField, "i")
t.assertEqual(search._query, "i", "native text input reaches SearchView Lua state")
t.assertEqual(search:resultCount(), 2, "text callback filters matching files")
t.assertEqual(search._resultsView.rowCount, 2,
	"matching rows replace the outline datasource")
t.expect(search:isExpanded(), "matching results expand SearchView")
width, height = dimensions(search._panel)
t.assertEqual(height, 360, "matching results use the expanded height")

bridge._textFieldTestInput(search._searchField, "missing")
t.assertEqual(search:resultCount(), 0, "missing query has no results")
t.assertEqual(search._resultsView.rowCount, 0,
	"no matches clear the outline datasource")
t.expect(not search:isExpanded(), "no matches collapse SearchView")
width, height = dimensions(search._panel)
t.assertEqual(height, 48, "no matches restore the input-bar height")

bridge._textFieldTestInput(search._searchField, "i")
t.assertEqual(search:resultCount(), 2,
	"collapse and expand preserve configured files")

-- Down and Return are delivered through the generic text command callback.
local handled = bridge._textFieldTestCommand(search._searchField, "moveDown")
t.expect(handled, "SearchView handles the moveDown text command")
handled = bridge._textFieldTestCommand(search._searchField, "submit")
t.expect(handled, "SearchView handles the submit text command")
t.assertEqual(selectedPath, "/tmp/test/utils.lua",
	"Return activates the keyboard-selected result")

-- A real parent window verifies generic panel presentation and first responder.
local window = ns.Window {
	title = "SearchView Test",
	width = 800,
	height = 600,
	appearance = "light",
	ns.VStack {},
}
search:show(window)
t.expect(ns.isFirstResponder(search._panel, search._searchField),
	"showing SearchView focuses the editable text field")
width, height = dimensions(search._panel)
t.assertEqual(height, 48, "show resets SearchView to its collapsed state")

handled = bridge._textFieldTestCommand(search._searchField, "cancel")
t.expect(handled, "SearchView handles the cancel text command")

search:setFiles { "/tmp/one.md", "/tmp/two.lua" }
search:setQuery("two")
t.assertEqual(search:resultCount(), 1, "setFiles refreshes the Lua datasource")

search:setRootDir("/nonexistent/path/12345")
local ok = pcall(function()
	search:show(window)
	search:hide()
end)
t.expect(ok, "SearchView tolerates an unavailable search root")

t.assertThrows(function()
	SearchView {}
end, "SearchView requires an onSelect callback")

os.exit(t.summary() and 0 or 1)
