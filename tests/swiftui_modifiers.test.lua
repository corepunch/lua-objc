_G.__headless = true

-- SwiftUI modifiers and controls added for Diskmap: Gauge, segmented Picker, .help,
-- .monospacedDigit, .navigationSubtitle, .borderedProminent, .controlSize,
-- a native DisclosureGroup triangle, and Section headers in sidebar lists.
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")

local function read(path)
	local file = assert(io.open(path)); local body = file:read("*a"); file:close()
	return body
end

-- Gauge is AppKit's continuous capacity level indicator.
local gauge = xml.render('<Gauge value="0.25" tint="systemMint" accessibilityLabel="Share of storage" />', {}, ns)
t.assertEqual(gauge.className, "NSLevelIndicator", "Gauge is a native level indicator")
t.assertEqual(gauge.levelIndicatorStyle, 1, "Gauge uses the continuous capacity style")
t.assertEqual(gauge.doubleValue, 0.25, "Gauge shows its value")
t.expect(not gauge.editable, "Gauge is read-only")
t.expect(gauge.fillColor ~= nil, "Gauge tint becomes the fill color")
t.assertEqual(gauge.accessibilityLabel, "Share of storage", "Gauge names what it measures")
t.assertEqual(xml.render('<Gauge value="3" />', {}, ns).doubleValue, 1, "Gauge clamps to its range")
local ranged = xml.render('<Gauge value="50" minValue="0" maxValue="200" />', {}, ns)
t.assertEqual(ranged.maxValue, 200, "Gauge accepts a custom range")
t.assertEqual(ranged.doubleValue, 50, "a ranged Gauge keeps its value")

-- .help is the native tooltip on any view.
t.assertEqual(xml.render('<Button title="Go" help="Opens the thing" />', {}, ns).toolTip, "Opens the thing",
	"help sets a button tooltip")
t.assertEqual(xml.render('<Label text="GB" help="Decimal gigabytes" />', {}, ns).toolTip, "Decimal gigabytes",
	"help sets a label tooltip")

-- .monospacedDigit keeps changing numbers from shifting.
local ones = xml.render('<Label text="1111" size="13" monospacedDigit="true" />', {}, ns)
local eights = xml.render('<Label text="8888" size="13" monospacedDigit="true" />', {}, ns)
t.expect(math.abs(ones.fittingSize.width - eights.fittingSize.width) < 0.5, "monospaced digits share one width")
t.assertEqual(ones.font.pointSize, 13, "monospaced digits keep the requested size")
local rounded = xml.render('<Label text="42 GB" size="20" design="rounded" monospacedDigit="true" />', {}, ns)
t.assertEqual(rounded.font.pointSize, 20, "monospaced digits combine with a font design")

-- .navigationSubtitle: the window subtitle sits beneath its title.
local window = ns.Window { title = "Diskmap", subtitle = "157 GB free", width = 320, height = 200, visible = false }
t.assertEqual(window.subtitle, "157 GB free", "Window subtitle is the native NSWindow subtitle")
window.subtitle = "150 GB free"
t.assertEqual(window.subtitle, "150 GB free", "Window subtitle updates in place")
window:close()

-- .borderedProminent and .controlSize.
local prominent = xml.render('<Button title="Review" style="borderedProminent" controlSize="large" />', {}, ns)
t.expect(prominent.bezelColor ~= nil, "borderedProminent fills the bezel with the accent color")
t.assertEqual(prominent.controlSize, 3, "controlSize large is NSControlSizeLarge")
t.assertEqual(xml.render('<Button title="Review" />', {}, ns).bezelColor, nil, "ordinary buttons keep the system bezel")
t.assertEqual(xml.render('<Button title="Small" controlSize="small" />', {}, ns).controlSize, 1, "controlSize small")
t.expect(not pcall(xml.render, '<Button title="Bad" controlSize="huge" />', {}, ns), "unknown control sizes fail loudly")

-- DisclosureGroup is the AppKit disclosure triangle beside its label.
local group, refs = xml.render('<DisclosureGroup label="Details" expanded="false"><Label id="body" text="Hidden" /></DisclosureGroup>', {}, ns)
local header = group.subviews[1]
local triangle, label = header.subviews[1], header.subviews[2]
t.assertEqual(triangle.bezelStyle, 5, "the disclosure control is a native disclosure triangle")
t.assertEqual(triangle.state, 0, "a collapsed group points its triangle sideways")
t.assertEqual(label.title, "Details", "the label sits beside the triangle")
t.expect(refs.body.superview.hidden, "collapsed content is hidden")
ns._invokeAction(label)
t.assertEqual(triangle.state, 1, "clicking the label turns the triangle down")
t.expect(not refs.body.superview.hidden, "expanding shows the content")
ns._invokeAction(label)
t.expect(refs.body.superview.hidden, "clicking again collapses the content")

-- .pickerStyle(.segmented) is NSSegmentedControl; the default stays a pop-up.
local picked
local segmented = xml.render('<Picker style="segmented" value="1" onChange="pick"><Option title="All" /><Option title="Unavailable" /><Option title="Unused" /></Picker>',
	{actions = {pick = function(index) picked = index end}}, ns)
t.assertEqual(segmented.className, "NSSegmentedControl", "a segmented picker is a native segmented control")
t.assertEqual(segmented.segmentCount, 3, "each option is a segment")
t.assertEqual(segmented.selectedSegment, 1, "the value selects a segment")
t.expect(segmented.frame.size.width >= segmented.fittingSize.width - 1, "segments fit their labels")
segmented.selectedSegment = 2
ns._invokeAction(segmented)
t.assertEqual(picked, 2, "the change callback receives the zero-based segment")
t.assertEqual(xml.render('<Picker><Option title="A" /></Picker>', {}, ns).className, "NSPopUpButton", "the default picker is a pop-up")

-- Sidebar sections are native group rows.
local list = xml.render('<List style="sourceList" header="false"><Column id="name" /></List>', {}, ns)
list:replaceRows({{section = true, title = "Storage"}, {name = "Overview"}})
local sectionCell = bridge._tableCell(list, 0, 0)
t.assertEqual(sectionCell.textField.stringValue, "Storage", "a section row shows its title")
t.assertEqual(sectionCell.textField.font.pointSize, 11, "section headers use the small header size")
t.assertEqual(bridge._tableCell(list, 0, 1).textField.stringValue, "Overview", "ordinary rows follow the header")
local tableSource = read("src/appkit/table_data_source.m")
t.expect(tableSource:find("isGroupRow:(NSInteger)row", 1, true) ~= nil, "AppKit marks section rows as group rows")
t.expect(tableSource:find("shouldSelectRow:(NSInteger)row", 1, true) ~= nil, "section rows cannot be selected")
t.expect(read("src/uikit/table_data_source.m"):find('rowData[@"section"]', 1, true) ~= nil, "UIKit styles section rows too")

-- New semantic colors resolve on both platforms.
t.expect(tostring(ns.Color("systemMint").description):find("Mint", 1, true) ~= nil, "systemMint is a semantic color")
t.expect(tostring(ns.Color("systemCyan").description):find("Cyan", 1, true) ~= nil, "systemCyan is a semantic color")
local uikitViews = read("src/uikit/views.m")
t.expect(uikitViews:find("systemMintColor", 1, true) and uikitViews:find("quaternaryLabelColor", 1, true),
	"UIKit resolves the same color names")
t.expect(read("src/uikit/platform.m"):find("monospacedDigitSystemFontOfSize", 1, true) ~= nil,
	"UIKit supports monospaced digits")

os.exit(t.summary() and 0 or 1)
