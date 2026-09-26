_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- SwiftUI tabViewBottomAccessory: one view declared beside the tabs.
local tabs, refs = xml.render([[
<TabView id="tabs">
	<Tab title="Library" systemImage="books.vertical"><Label text="Library" /></Tab>
	<Tab title="Search" systemImage="magnifyingglass"><Label text="Search" /></Tab>
	<TabAccessory hidden="true">
		<HStack id="nowReading" spacing="8">
			<Label id="nowReadingTitle" text="Zork I" />
		</HStack>
	</TabAccessory>
</TabView>]], {}, ns)
t.assertEqual(tabs.numberOfTabViewItems, 2, "an accessory is not a tab")
t.expect(tabs.accessoryView ~= nil, "the tab view retains its accessory view")
t.expect(tabs.accessoryHidden == true, "the accessory starts hidden when declared hidden")
t.assertEqual(refs.nowReadingTitle.text, "Zork I", "accessory content is addressable by id")
tabs.accessoryHidden = false
t.expect(tabs.accessoryHidden == false, "the accessory can be enabled later")
refs.nowReadingTitle.text = "Planetfall"
t.assertEqual(refs.nowReadingTitle.text, "Planetfall", "accessory content updates in place")

local ok, err = pcall(xml.render, [[
<TabView>
	<Tab title="A"><Label text="A" /></Tab>
	<TabAccessory><Label text="1" /></TabAccessory>
	<TabAccessory><Label text="2" /></TabAccessory>
</TabView>]], {}, ns)
t.expect(not ok and tostring(err):find("one <TabAccessory>", 1, true) ~= nil,
	"a tab view accepts one accessory")
local ok2, err2 = pcall(xml.render, [[<TabView><TabAccessory></TabAccessory></TabView>]], {}, ns)
t.expect(not ok2 and tostring(err2):find("requires one view", 1, true) ~= nil,
	"an accessory requires exactly one view")

local uikit = assert(io.open("src/uikit/navigation.m", "r")):read("*a")
t.expect(uikit:find("UITabAccessory alloc] initWithContentView", 1, true) ~= nil
		and uikit:find("setBottomAccessory:", 1, true) ~= nil,
	"UIKit uses the native iOS 26 tab bar accessory")
