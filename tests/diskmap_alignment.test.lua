_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Alignment (AGENTS.md, "Alignment"): in a block of rows that lead with a
-- symbol, every symbol is centered on one vertical line and every label
-- starts at one edge, whatever the symbols' own widths.

-- The x of a view's leading edge in its window.
local function windowX(view)
	local x = 0
	while view do
		x = x + view.frame.origin.x
		view = view.superview
	end
	return x
end

-- Every visible stack under `root` that leads with a symbol: the symbol's
-- center and the leading edge of what follows it. Collapsed disclosure
-- content is skipped: a note there carries its symbol inside its sentence.
local function symbolRows(root, rows)
	rows = rows or {}
	if root.hidden then return rows end
	local subviews = root.subviews
	local first = subviews[1]
	if first and first.className == "LuaSymbolImageView" and subviews[2] then
		table.insert(rows, {center = windowX(first) + first.frame.size.width / 2, label = windowX(subviews[2])})
	end
	for _, child in ipairs(subviews) do symbolRows(child, rows) end
	return rows
end

local function assertOneColumn(rows, minimum, tag)
	t.expect(#rows >= minimum, tag .. " has its symbol rows (" .. #rows .. ")")
	for index, row in ipairs(rows) do
		t.expect(math.abs(row.center - rows[1].center) < 0.01, tag .. " symbol " .. index .. " is centered on the column's line")
		t.expect(math.abs(row.label - rows[1].label) < 0.01, tag .. " label " .. index .. " starts at the column's text edge")
	end
end

-- The Overview card on a nearly full disk: the low-space warning, the legend
-- dots, the hidden-space symbols share one column; the leading cleanup action is a separate block.
local service = Mock.new()
service.availableBytes = service.fixture.capacityBytes * 0.05
local app = Controller.new(service)
local window = app:createWindow()
bridge._flushLayout()
local hero = app.page.refs
t.expect(hero.lowSpace ~= nil, "a nearly full disk shows the low-space warning")
t.expect(hero.legend ~= nil and hero.hiddenSpace ~= nil, "the card lists categories and hidden space")
local column = hero.legend.superview
local legend, hidden = #hero.legend.subviews, #hero.hiddenSpace.subviews
-- The warning, each legend and hidden-space row.
assertOneColumn(symbolRows(column), 1 + legend + hidden, "the Overview card")

-- The "could not measure" card: its own symbol and each reason's symbol share
-- one column, and the title, each reason's name and what is written under it
-- start at one edge.
local notMeasured = app.page.refs
t.expect(notMeasured.notMeasuredCard ~= nil, "the Overview explains what was not measured")
local reasons = symbolRows(notMeasured.notMeasuredCard)
assertOneColumn(reasons, 2, "the not-measured card")
local function tableColumns(list)
	local cell = bridge._tableCell(list, 0, 0)
	local frame = bridge._tableCellFrames(list, 0)[1]
	-- The headless helper asks the native delegate for a detached cell.
	-- AppKit supplies its position separately through frameOfCellAtColumn.
	local x = windowX(list.documentView) + frame.x
	return x + cell.imageView.frame.origin.x + cell.imageView.frame.size.width / 2,
		x + cell.textField.frame.origin.x
end
local categoryCenter, categoryText = tableColumns(hero.results)
for index, row in ipairs(reasons) do
	t.assertEqual(row.center, categoryCenter, "not-measured symbol " .. index .. " shares the category image column")
	t.assertEqual(row.label, categoryText, "not-measured text " .. index .. " shares the category text column")
end
local explained = 0
for id, reason in pairs(notMeasured) do
	if id:find("^unmeasured_") then
		local title, body = reason.subviews[1], reason.subviews[2]
		t.assertEqual(windowX(body.subviews[1]), windowX(title.subviews[2]), id .. ": the explanation starts at the name's edge")
		local symbol, name = title.subviews[1], title.subviews[2]
		t.expect(math.abs((symbol.frame.origin.y + symbol.frame.size.height / 2) - (name.frame.origin.y + name.frame.size.height / 2)) <= 0.5,
			id .. ": the symbol and the name share a center line")
		explained = explained + 1
	end
end
t.expect(explained > 0, "the card names its reasons")

-- Shared recommendation cards use the same columns as the native lists on
-- their pages, rather than a larger icon and an unrelated inset.
for _, id in ipairs({"cleanup", "applications", "files", "worktrees", "kinds", "updates"}) do
	app:show(id)
	bridge._flushLayout()
	local refs = app.page.refs
	local list
	local function firstList(view)
		if list then return end
		if view.className == "LuaScrollView" and view.documentView.className == "NSTableView" and view.rowCount > 0 then
			list = view
			return
		end
		for _, child in ipairs(view.subviews) do firstList(child) end
	end
	firstList(refs.pageContent)
	t.expect(list ~= nil and refs.decisionTitle ~= nil, id .. " has a recommendation and native list")
	local center, text = tableColumns(list)
	local title = refs.decisionTitle
	local row = title.superview.superview
	local symbol = row.subviews[1]
	t.assertEqual(windowX(symbol) + symbol.frame.size.width / 2, center, id .. " recommendation shares the list icon column")
	t.assertEqual(windowX(title), text, id .. " recommendation shares the list text column")
	if id == "cleanup" then
		for index, tip in ipairs(symbolRows(refs.tips)) do
			t.assertEqual(tip.center, center, "cleanup tip " .. index .. " shares the list icon column")
			t.assertEqual(tip.label, text, "cleanup tip " .. index .. " shares the list text column")
		end
		t.expect(#symbolRows(refs.tips) > 0, "cleanup has tips to align with its list")
	end
	if id == "updates" then
		local checked = 0
		local function compareCards(view)
			if view.className == "NSBox" then
				for index, item in ipairs(symbolRows(view)) do
					checked = checked + 1
					t.assertEqual(item.center, center, "update card row " .. index .. " shares the installer icon column")
					t.assertEqual(item.label, text, "update card row " .. index .. " shares the installer text column")
				end
				return
			end
			for _, child in ipairs(view.subviews) do compareCards(child) end
		end
		compareCards(refs.pageContent)
		t.expect(checked >= 7, "updates aligns the recommendation, status, stages and snapshots")
	end
end

-- Pages whose rows lead with symbols of different widths.
for _, id in ipairs({"updates", "guide", "help", "cleanup"}) do
	app:show(id)
	bridge._flushLayout()
	local sections = {}
	-- Rows are compared within their card: a card is one block.
	local function cards(view)
		if view.className == "LuaGroupBox" or view.className == "NSBox" then table.insert(sections, view); return end
		for _, child in ipairs(view.subviews) do cards(child) end
	end
	cards(app.page.refs.pageContent)
	local checked = 0
	for index, card in ipairs(sections) do
		local rows = symbolRows(card)
		if #rows > 1 then
			assertOneColumn(rows, 2, id .. " card " .. index)
			checked = checked + 1
		end
	end
	if id ~= "cleanup" then t.expect(checked > 0, id .. " has symbol rows to align") end
end

-- A disclosure triangle is one more symbol: `indicatorWidth` centers it in
-- the rows' symbol column; its label and content start at their text edge.
app:show("guide")
bridge._flushLayout()
local topics = 0
for id, group in pairs(app.page.refs) do
	if id:find("^details_") then
		local row = app.page.refs["topic_" .. id:sub(#"details_" + 1)].subviews[1]
		local symbol, title = row.subviews[1], row.subviews[2]
		local header, content = group.subviews[1], group.subviews[2]
		local triangle, label = header.subviews[1], header.subviews[2]
		t.assertEqual(triangle.bezelStyle, 5, "the header leads with the native disclosure triangle")
		t.assertEqual(windowX(triangle) + triangle.frame.size.width / 2, windowX(symbol) + symbol.frame.size.width / 2, id .. ": the triangle is centered under the topic's symbol")
		t.assertEqual(windowX(label), windowX(title), id .. ": the disclosure label starts at the title's edge")
		ns._invokeAction(label)
		bridge._flushLayout()
		t.assertEqual(windowX(content.subviews[1]), windowX(title), id .. ": disclosed content starts at the same edge")
		topics = topics + 1
	end
end
t.expect(topics > 0, "the guide has topics with details")
local plain = xml.render('<DisclosureGroup label="Details"><Label text="Body" /></DisclosureGroup>', {}, ns)
t.assertEqual(plain.subviews[1].subviews[1].frame.origin.x, 0, "without indicatorWidth the triangle stays at the leading edge")
t.assertEqual(plain.subviews[2].subviews[1].frame.origin.x, 0, "and its content is not indented")

-- "Worth a look" marks with a native checkbox, not a worded button: a
-- title that changed from Mark to Marked widened the button and pushed its
-- row's size out of line. Checking a row must not move anything: the boxes
-- and the header symbol share one centre line, names start at one edge and
-- sizes end at one edge, before and after.
app:show("map")
local function centerX(view) local f = view.frameInWindow; return f.origin.x + f.size.width / 2 end
local function marks(width, height, marked)
	local page = app.page.refs.page
	page.size = ns.Size(width, height)
	page:layout(width)
	local rows = {}
	for index = 1, 3 do
		local box = app.page.refs["worthMark_" .. index]
		if box then
			local row = box.superview.superview
			table.insert(rows, {box = box, name = row.subviews[2], size = row.subviews[3], header = row.superview.subviews[1]})
		end
	end
	t.expect(#rows > 0, "the map has suggestions to mark")
	local first = rows[1]
	local headerSymbol = first.header.subviews[1]
	for index, row in ipairs(rows) do
		local label = "row " .. index .. " at " .. width .. (marked and " marked" or "")
		t.assertEqual(row.box.className, "NSButton", label .. " marks with a native checkbox")
		t.assertEqual(row.box.title, "", label .. " has no word beside its box")
		t.assertEqual(row.box.state, (index == 1 and marked) and 1 or 0, label .. " shows its marked state")
		t.assertEqual(row.box.accessibilityLabel, "Mark " .. row.name.text .. " for cleanup", label .. " names its action for VoiceOver")
		t.assertEqual(centerX(row.box), centerX(headerSymbol), label .. " centres its box on the header symbol")
		t.assertEqual(row.name.frameInWindow.origin.x, first.header.subviews[2].frameInWindow.origin.x, label .. " starts its name at the header title")
		local f, g = row.size.frameInWindow, first.size.frameInWindow
		t.assertEqual(f.origin.x + f.size.width, g.origin.x + g.size.width, label .. " ends its size on the shared edge")
	end
	return rows[1].size.frameInWindow.origin.x
end
for _, size in ipairs({{width = 950, height = 580}, {width = 1400, height = 900}}) do
	local before = marks(size.width, size.height, false)
	app.page.refs.worthMark_1.state = 1
	ns._invokeAction(app.page.refs.worthMark_1)
	t.assertEqual(marks(size.width, size.height, true), before, "marking leaves the size where it was")
	app.page.refs.worthMark_1.state = 0
	ns._invokeAction(app.page.refs.worthMark_1)
	t.assertEqual(marks(size.width, size.height, false), before, "and so does clearing it")
end

window:close()

os.exit(t.summary() and 0 or 1)
