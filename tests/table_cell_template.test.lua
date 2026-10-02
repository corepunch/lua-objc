_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")

-- A <Column> with child XML renders that template in every row, bound to
-- the row's fields (SwiftUI `TableColumn { row in ... }`).
local TEMPLATE = [[<VStack>
	<List id="list" style="fullWidth" header="false" rowHeight="40" maxWidth="infinity" height="200">
		<Column id="name" title="Item" minWidth="100" />
		<Column id="usage" title="Usage" width="200">
			<VStack spacing="2" alignment="leading">
				<HStack spacing="4" maxWidth="infinity">
					<SystemImage id="icon" name="$icon" color="$tint" size="13" visible="$icon" />
					<Label id="title" text="$title" color="$tint" truncation="tail" help="$note" />
					<Spacer />
					<Label id="detail" text="$detail" color="secondary" fixedSize="horizontal" hidden="$quiet" />
				</HStack>
				<HStack spacing="4">
					<Label id="price" text="$$3.9k" />
					<Label id="nested" text="$stats.label" color="$stats.tint" />
				</HStack>
				<Gauge id="gauge" value="$fraction" tint="$tint" enabled="$fraction" accessibilityLabel="$accessibility" maxWidth="infinity" />
				<Label id="off" text="off" disabled="$quiet" />
			</VStack>
		</Column>
	</List>
</VStack>]]

local window = ns.Window { visible = false, width = 400, height = 240 }
local root, refs = xml.render(TEMPLATE, {}, ns)
local list = refs.list
t.assertEqual(refs.title, nil, "a template's views belong to cells, not to the screen's refs")
list:replaceRows({
	{name = "Full", title = "Photos", detail = "3 of 4 {GB}", accessibility = "Usage of Photos", fraction = 0.75, tint = "systemRed", icon = "photo", note = "Library", stats = {label = "Deep", tint = "systemBlue"}},
	{name = "Bare", title = "Mail"},
	{name = "Quiet", title = "Music", detail = "1 of 2", fraction = 0, quiet = true},
	{name = "Odd", title = 42, fraction = 7, icon = "", quiet = false},
})
window:add(root)
window:layout()
bridge._appkitLayout(window)

local function views(cell)
	cell:layout()
	local found = {}
	local function visit(view)
		local id = view.accessibilityIdentifier
		if id and id ~= "" then found[id] = view end
		for _, child in ipairs(view.subviews) do visit(child) end
	end
	visit(cell)
	return found
end
local function row(index) return views(bridge._tableCell(list, 1, index)) end
local function color(name) return tostring(bridge._systemColor(name)) end

t.assertEqual(bridge._tableCell(list, 1, 0).className, "LuaTemplateCellView", "a column with content renders its template")
t.assertEqual(bridge._tableCell(list, 0, 0).className, "LuaTableCellView", "a column without content keeps its text cell")
t.assertEqual(bridge._tableCell(list, 0, 0).textField.stringValue, "Full", "text columns still show row[id]")

-- $field: typed values.
local full = row(0)
t.assertEqual(full.title.text, "Photos", "text binds a row field")
t.assertEqual(full.gauge.doubleValue, 0.75, "a number stays a number")
t.assertEqual(tostring(full.title.textColor), color("systemRed"), "a colour binds by semantic name")
t.assertEqual(tostring(full.gauge.fillColor), color("systemRed"), "one field can bind several attributes")
t.assertEqual(full.icon.symbolName, "photo", "a symbol binds by name")
t.expect(full.icon.image ~= nil, "the bound symbol is drawn")
t.assertEqual(full.title.toolTip, "Library", "help binds the tooltip")

-- Composed strings are fields the model prepares; braces are ordinary text.
t.assertEqual(full.detail.text, "3 of 4 {GB}", "a prepared string binds whole")
t.assertEqual(full.gauge.accessibilityLabel, "Usage of Photos", "accessibility labels bind a prepared field")
t.assertEqual(full.price.text, "$3.9k", "$$ is a literal dollar sign")
t.assertEqual(full.nested.text, "Deep", "a path reaches into a nested field")
t.assertEqual(tostring(full.nested.textColor), color("systemBlue"), "a path binds a colour")
t.assertEqual(row(1).nested.text, "", "a missing parent is a missing field")

-- Attribute pairs and truthiness.
t.expect(not full.icon.hidden, "visible=\"$field\" shows the view when the field is present")
t.expect(full.gauge.enabled, "enabled=\"$field\" enables the control when the field is present")
t.expect(full.off.enabled, "disabled=\"$field\" enables the control when the field is missing")
t.expect(not full.detail.hidden, "hidden=\"$field\" shows the view when the field is missing")
local quiet = row(2)
t.expect(quiet.detail.hidden, "hidden=\"$field\" hides the view when the field is true")
t.expect(not quiet.off.enabled, "disabled=\"$field\" disables the control when the field is true")
t.expect(quiet.gauge.enabled and quiet.gauge.doubleValue == 0, "zero is a value: present, and shown as zero")
local odd = row(3)
t.expect(odd.icon.hidden, "an empty string counts as missing")
t.expect(not odd.detail.hidden, "false counts as missing")
t.assertEqual(odd.title.text, "42", "a number binds to text as its description")
t.assertEqual(odd.gauge.doubleValue, 1, "a gauge clamps a value beyond its range")

-- A row without the field returns the attribute to what the view was built with.
local bare = row(1)
t.assertEqual(bare.title.text, "Mail", "present fields bind")
t.assertEqual(tostring(bare.title.textColor), color("label"), "a missing colour is the label's own")
t.assertEqual(bare.gauge.doubleValue, 0, "a missing number is the gauge's own value")
t.expect(not bare.gauge.enabled, "a missing fraction disables the gauge")
t.expect(bare.icon.hidden and bare.icon.image == nil, "a missing symbol is no symbol")
t.expect(bare.title.toolTip == nil or bare.title.toolTip == "", "a missing tooltip is none")

-- One cell given another row shows nothing of the previous one.
list:replaceRows({{name = "Bare", title = "Mail"}})
window:layout()
local reused = row(0)
t.assertEqual(reused.title.text, "Mail", "a reused cell shows its new row")
t.assertEqual(tostring(reused.title.textColor), color("label"), "a reused cell drops the previous colour")
t.assertEqual(reused.gauge.doubleValue, 0, "a reused cell drops the previous value")
t.expect(reused.icon.hidden and reused.icon.image == nil, "a reused cell drops the previous symbol")

-- Layout is the framework's: the content takes the column inside the text
-- cells' insets and its own height, centred in the row.
list:replaceRows({{name = "Full", title = "Photos", used = 3, total = 4, fraction = 0.75, icon = "photo"}})
window:layout()
local cell = bridge._tableCell(list, 1, 0)
local laid = views(cell)
local content = cell.subviews[1]
t.assertEqual(content.frame.origin.x, 8, "content starts at the text cells' leading inset")
t.assertEqual(content.frame.size.width, cell.frame.size.width - 16, "content spans the column inside its insets")
t.expect(math.abs((content.frame.origin.y + content.frame.size.height / 2) - cell.frame.size.height / 2) <= 0.5,
	"content is centred in the row")
t.expect(content.frame.size.height <= cell.frame.size.height, "content fits the row height")
local gauge, title, detail = laid.gauge.frameInWindow, laid.title.frameInWindow, laid.detail.frameInWindow
t.assertEqual(gauge.size.width, content.frame.size.width, "maxWidth=\"infinity\" fills the column")
t.expect(title.origin.y >= gauge.origin.y + gauge.size.height, "the stack places the line above the gauge")
t.expect(detail.origin.x + detail.size.width >= gauge.origin.x + gauge.size.width - 1, "the spacer pushes the detail to the trailing edge")
t.expect(laid.icon.frameInWindow.origin.x + laid.icon.frameInWindow.size.width <= title.origin.x, "the symbol leads the title")

-- Truncation: the fixed-size detail keeps its width; the title gives way.
list:replaceRows({{name = "Long", title = "An extraordinarily long title that cannot possibly fit the column", used = 3, total = 4, fraction = 0.5}})
window:layout()
local long = row(0)
t.expect(long.detail.frame.size.width >= long.detail.fittingSize.width, "a fixedSize label keeps its width")
t.expect(long.title.frame.size.width < long.title.fittingSize.width, "the flexible label truncates")
t.assertEqual(long.title.lineBreakMode, 4, "and truncates at its tail")
t.expect(long.title.frameInWindow.origin.x + long.title.frameInWindow.size.width <= long.detail.frameInWindow.origin.x,
	"a truncated title stops before the detail")

-- Accessibility and selection read the cell's outlets.
local outlets = bridge._tableCell(list, 1, 0)
t.assertEqual(outlets.textField.accessibilityIdentifier, "title", "the first label is the cell's text field")
t.assertEqual(outlets.imageView.accessibilityIdentifier, "icon", "the first image is the cell's image view")
outlets.backgroundStyle = 1
t.assertEqual(views(outlets).detail.cell.backgroundStyle, 1, "a selected row's emphasis reaches labels inside stacks")
outlets.backgroundStyle = 0
t.assertEqual(views(outlets).detail.cell.backgroundStyle, 0, "and leaves with the selection")

-- Selection and keyboard focus are the table's, untouched by templates.
list:replaceRows({{name = "A", title = "One"}, {name = "B", title = "Two"}})
local selected
list:onRowSelect(function(_, index) selected = index end)
list:selectRow(1)
t.assertEqual(list.documentView.selectedRow, 1, "rows with templates select")
t.expect(list.documentView.acceptsFirstResponder, "the table keeps keyboard focus")

-- Outlines share the cells.
local outline = xml.render([[<OutlineView header="false" rowHeight="40" style="fullWidth">
	<Column id="name" />
	<Column id="usage" width="160"><Gauge id="gauge" value="$fraction" maxWidth="infinity" /></Column>
</OutlineView>]], {}, ns)
outline:replaceRows({{id = "a", name = "Parent", fraction = 0.5, expanded = true, children = {{id = "b", name = "Child", fraction = 0.25}}}})
outline.size = ns.Size(400, 200); outline:layout(400)
t.assertEqual(views(bridge._tableCell(outline, 1, 0)).gauge.doubleValue, 0.5, "an outline row binds its template")
t.assertEqual(views(bridge._tableCell(outline, 1, 1)).gauge.doubleValue, 0.25, "and so does its child")

-- Lua column specs take the same factory the XML renderer builds.
local built = 0
local direct = ns.List {
	columns = {
		{ id = "name", title = "Name" },
		{ id = "level", title = "Level", width = 120, template = function()
			built = built + 1
			local gauge = ns.Gauge { value = 0 }
			return gauge, { { view = gauge, key = "doubleValue", kind = "number", path = { "level" } } }
		end },
	},
	data = { { name = "One", level = 0.4 } },
}
t.assertEqual(bridge._tableCell(direct, 1, 0).subviews[1].doubleValue, 0.4, "a Lua column template binds natively")
t.expect(built >= 1, "the factory builds the cell")

-- Mistakes fail when the screen renders, not while it scrolls.
local function rejects(columnBody, pattern, message)
	local ok, err = pcall(xml.render, '<List><Column id="a">' .. columnBody .. '</Column></List>', {}, ns)
	t.expect(not ok and tostring(err):find(pattern) ~= nil, message .. " (" .. tostring(err) .. ")")
end
rejects('<Label text="$a" size="$b" />', "cannot bind size", "an attribute without a binding is rejected")
rejects('<Label text="Used $a of $b" />', "exactly one %$path", "interpolation is rejected")
rejects('<Label text="$a + $b" />', "exactly one %$path", "expressions are rejected")
rejects('<Label text="$!a" />', "exactly one %$path", "negation is rejected; use visible/hidden")
rejects('<Label text="$a..b" />', "empty path segment", "an empty path segment is rejected")
rejects('<Label text="$a" /><Label text="$b" />', "must be one view", "a template has one root")
local plain = xml.render('<Label text="{a}" />', {}, ns)
t.assertEqual(plain.text, "{a}", "outside a column, braces are ordinary text")

-- Large tables: cells are reused, and giving a cell its row runs no Lua.
-- Scrolling 10,000 rows builds about one screen of cells.
local bigWindow = ns.Window { visible = false, width = 400, height = 440 }
local bigRoot, bigRefs = xml.render([[<VStack>
	<List id="list" style="fullWidth" header="false" rowHeight="44" maxWidth="infinity" height="440">
		<Column id="name" minWidth="100" />
		<Column id="usage" width="200">
			<VStack spacing="2">
				<Label text="$title" truncation="tail" />
				<Gauge value="$fraction" maxWidth="infinity" />
			</VStack>
		</Column>
	</List>
</VStack>]], {}, ns)
local many = {}
for index = 1, 10000 do
	table.insert(many, { name = "Row " .. index, title = "Item " .. index, fraction = (index % 100) / 100 })
end
bigRefs.list:replaceRows(many)
bigWindow:add(bigRoot)
bigWindow:layout()
bridge._appkitLayout(bigWindow)
local visibleRows = math.ceil(440 / 44)
local firstScreen = bridge._tableTemplateCells(bigRefs.list)
t.expect(firstScreen >= 1 and firstScreen <= visibleRows + 2, "the first screen builds only its visible cells (" .. firstScreen .. ")")
-- A scroll step that builds no cell makes one Lua call: the test's own
-- call into the layout pass. Binding the rows it reveals makes none.
local luaCalls, reusedSteps, reusedCalls = 0, 0, 0
debug.sethook(function() luaCalls = luaCalls + 1 end, "c")
for index = 0, 9999, 250 do
	bigRefs.list:selectRow(index)
	local builtBefore, callsBefore = bridge._tableTemplateCells(bigRefs.list), luaCalls
	bridge._appkitLayout(bigWindow)
	local calls = luaCalls - callsBefore
	if bridge._tableTemplateCells(bigRefs.list) == builtBefore then
		reusedSteps = reusedSteps + 1
		reusedCalls = reusedCalls + calls
	end
end
debug.sethook()
local built = bridge._tableTemplateCells(bigRefs.list)
t.expect(built <= 2 * (visibleRows + 2), "scrolling 10,000 rows reuses its cells (" .. built .. " built)")
t.expect(reusedSteps >= 30, "most scroll steps reuse every cell (" .. reusedSteps .. " of 40)")
t.assertEqual(reusedCalls, reusedSteps, "binding rows while scrolling runs no Lua")
local last = bridge._tableCell(bigRefs.list, 1, 9999)
t.assertEqual(last.textField.text, "Item 10000", "the last row binds its own fields")

-- SwiftUI `.lineLimit(2).truncationMode(.tail)`: a detail too long for its
-- column wraps onto a second line and truncates only the last.
local wrapWindow = ns.Window { visible = false, width = 400, height = 120 }
local wrapRoot, wrapRefs = xml.render([[<VStack>
	<List id="list" style="fullWidth" header="false" rowHeight="44" maxWidth="infinity" height="100">
		<Column id="name" minWidth="100" />
		<Column id="detail" width="150"><Label text="$detail" lines="2" truncation="tail" /></Column>
	</List>
</VStack>]], {}, ns)
wrapRefs.list:replaceRows({{name = "a", detail = "main · 1 uncommitted change, 1 unpushed"}, {name = "b", detail = "Not in git"}})
wrapWindow:add(wrapRoot)
wrapWindow:layout()
bridge._appkitLayout(wrapWindow)
local function detailLabel(index)
	local cell = bridge._tableCell(wrapRefs.list, 1, index)
	cell:layout()
	return cell.subviews[1]
end
local wrapped, short = detailLabel(0), detailLabel(1)
local lineHeight = math.ceil(wrapped.font.ascender - wrapped.font.descender + wrapped.font.leading)
t.assertEqual(wrapped.frame.size.height, 2 * lineHeight, "a long detail takes two whole lines, so the second draws")
t.expect(wrapped.cell.wraps and not wrapped.cell.usesSingleLineMode, "the long detail wraps")
t.assertEqual(wrapped.lineBreakMode, 0, "the label renderer breaks a wrapped label by word")
t.expect(wrapped.cell.truncatesLastVisibleLine, "only the last line truncates")
t.assertEqual(short.frame.size.height, lineHeight, "a short detail stays one line")
local single = xml.render('<Label text="A long single line of text" truncation="tail" />', {}, ns)
t.assertEqual(single.lineBreakMode, 4, "a one-line label keeps its declared truncation")
t.expect(not single.cell.truncatesLastVisibleLine, "a label without a line limit truncates as declared")

os.exit(t.summary() and 0 or 1)
