_G.__headless = true
local t = require("TestKit")
local bridge = package.loaded.UIKitNative

if not bridge then
	-- macOS cannot load UIKit. Keep the native integration contract in the
	-- default suite; the same script exercises native geometry in the iOS host.
	local function source(path)
		local file = assert(io.open(path))
		local text = file:read("*a")
		file:close()
		return text
	end
	local navigation = source("src/uikit/navigation.m")
	local host = navigation:match("@implementation LuaToolbarItemHost(.-)\n@end")
	t.expect(host and host:find("intrinsicContentSize", 1, true)
		and host:find("measure_size(self.luaContent", 1, true),
		"custom navigation items publish their current content size, even when installed empty")
	t.expect(host and host:find("self.luaContent.frame = self.bounds", 1, true)
		and host:find("layout_recursive(self.luaContent", 1, true),
		"native toolbar sizing lays out retained content within UIKit's bounds")
	local invalidation = source("src/uikit/layout.m"):match("static void uikit_invalidate_layout(.-)\n}")
	t.expect(invalidation and invalidation:find("ancestor.superview", 1, true)
		and invalidation:find("[ancestor invalidateIntrinsicContentSize]", 1, true),
		"retained content updates invalidate the native navigation item's fitting size")
	os.exit(t.summary() and 0 or 1)
end

-- Run in the UIKit host with AppKitNative aliased to UIKitNative for TestKit.
-- No window or run-loop wait: the native parity probe flushes pending layout.
local ns = require("UIKit")
local xml = require("ui.xml")
local page, refs = xml.render([[
<Page title="Story" titleDisplayMode="inline">
	<Toolbar>
		<ToolbarItem id="title" placement="principal"><VStack id="heading" width="230" /></ToolbarItem>
		<ToolbarItem id="settings" placement="primaryAction" label="Settings" />
	</Toolbar>
	<Label id="body" text="Page content" />
</Page>]], {}, ns)
local item = page.navigationItem
local host = item.titleView
local settings = item.rightBarButtonItems[1]
t.assertEqual(host.intrinsicContentSize.height, 0, "the title can be installed before its template")

local TITLE = [[
<VStack spacing="1" alignment="center" maxWidth="infinity">
	<Label id="title" text="<%= title %>" size="15" lines="1" truncation="tail" maxWidth="infinity" />
	<% if room then %><Label id="room" text="<%= room %>" size="11" lines="1" truncation="tail" maxWidth="infinity" /><% end %>
</VStack>]]
local mounted
local function update(title, room)
	local description = xml.describe(TITLE, { title = title, room = room })
	if mounted then xml.reconcile(mounted, description, ns, refs.heading)
	else mounted = xml.mount(description, ns, refs.heading) end
end
local function layout(width)
	local size = host.intrinsicContentSize
	bridge._parityMeasure(host, {}, { width = width or size.width, height = size.height })
	return size
end

update("The Pocket Weather Bureau", "Dispatch Post")
local size = layout()
local title, room = mounted.refs.title, mounted.refs.room
local first, second = title.frame, room.frame
t.expect(size.height >= first.size.height + second.size.height + 1, "a late-mounted title reserves both lines")
t.expect(second.origin.y >= first.origin.y + first.size.height, "the room sits below the title without overlap")
t.expect(second.origin.y + second.size.height <= size.height, "both lines fit the native title view")
for _, width in ipairs({ 160, 230, 320 }) do
	layout(width)
	t.expect(title.frame.size.width <= width and room.frame.size.width <= width,
		"native item resizing constrains both title lines at width " .. width)
end
update("A much longer story title that must truncate", "A much longer room name that must truncate")
layout()
t.assertEqual(mounted.refs.title, title, "text updates retain the title label")
t.assertEqual(mounted.refs.room, room, "room changes retain the second label")
t.expect(room.frame.origin.y >= title.frame.origin.y + title.frame.size.height, "updated lines remain separated")
update("Story", nil)
local single = layout()
t.expect(single.height < size.height, "removing the room shrinks the native fitting height")
update("Story", "")
local empty = layout()
t.expect(empty.height >= single.height and empty.height <= size.height, "an empty room keeps a valid compact fitting height")
t.assertEqual(item.titleView, host, "updates retain the navigation title view")
t.assertEqual(item.rightBarButtonItems[1], settings, "title updates preserve sibling toolbar items")
t.assertEqual(refs.body.text, "Page content", "title updates leave page content unchanged")
xml.unmount(mounted, ns)
t.assertEqual(host.intrinsicContentSize.height, 0, "unmounting clears the title's fitting height")
return t.summary()
