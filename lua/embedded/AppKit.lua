-- AppKitNative is supplied by the host runtime. Keeping it private lets the
-- public AppKit module remain a single dylib with a stable declarative API.
local bridge = require("AppKitNative")

-- XML-generated native exports are the public module. Lua only adds compound
-- declarative components whose behavior cannot be expressed as a native class
-- declaration.
local AppKit = bridge
local Scope = require("ui.scope")(bridge)
AppKit.Scope = Scope

-- Native timers and network callbacks resume suspended Lua work later. Lua's
-- coroutine.resume returns failures instead of raising them, so centralize the
-- check here to preserve the same stderr visibility as native callbacks.
local function resumeCoroutine(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		io.stderr:write("coroutine error: " .. tostring(err) .. "\n")
	end
	return ok, err
end

local layout_properties = {
	"padding",
	"paddingHorizontal",
	"paddingLeading",
	"paddingTrailing",
	"paddingVertical",
	"paddingTop",
	"paddingBottom",
	"spacing",
	"alignment",
	"fixedWidth",
	"fixedHeight",
	"minWidth",
	"minHeight",
	"maxWidth",
	"maxHeight",
	"flexGrow",
	"flexShrink",
	"flexBasis",
	"fillWidth",
	"fillHeight",
	"hidden",
	"allowsHitTesting",
	"background",
	"cornerRadius",
	"clipsToBounds",
	"onClick",
	"onDoubleClick",
	"contextMenu",
	"hoverTooltip",
}

local function applyLayout(view, props)
	if type(props) ~= "table" then return view end
	for _, key in ipairs(layout_properties) do
		if props[key] ~= nil then
			if key == "background" then
				view.backgroundColor = bridge._systemColor(props[key])
			elseif key == "onClick" then
				bridge._addClick(view, props[key])
			elseif key == "onDoubleClick" then
				bridge._addDoubleClick(view, props[key])
			elseif key == "contextMenu" then
				bridge._addContextMenu(view, props[key])
			elseif key == "hoverTooltip" then
				local tt = props[key]
				bridge._addHoverTooltip(view, tt.title or "", tt.detail or "")
			else
				view[key] = props[key]
			end
		end
	end
	return view
end

local function addChildren(parent, children)
	for _, child in ipairs(children) do
		if type(child) == "userdata" then
			parent:add(child)
		elseif type(child) == "table" and child.__appkitGroup then
			addChildren(parent, child)
		end
	end
end

local function path_join(...)
	local parts = {...}
	local sep = package.config:sub(1, 1)
	return table.concat(parts, sep)
end

local function resolveImage(name)
	if name:sub(1, 1) == "/" or name:sub(1, 1) == "~" then
		return name
	end
	local f = io.open(name)
	if f then
		f:close()
		return name
	end
	return name
end

--- Creates the app window and hosts the rendered root view.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop appearance string optional. Window appearance: `system`, `light`, or `dark`.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop contentAccessory table optional. Accessory view attached to the window content area.
--- @prop detail table optional. Rendered detail pane view.
--- @prop detailWidth number optional. Requested width of the detail pane, in points.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop hideTitle boolean optional. Component-specific setting passed to the native control.
--- @prop minHeight number optional. Component-specific setting passed to the native control.
--- @prop minWidth number optional. Component-specific setting passed to the native control.
--- @prop sidebar table optional. Rendered navigation sidebar view.
--- @prop sidebarWidth number optional. Component-specific setting passed to the native control.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop tabbingIdentifier string optional. Identifier used to group tabbing windows.
--- @prop tabbingMode string optional. Window tabbing mode.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @prop toolbar table optional. Toolbar item descriptors.
--- @prop toolbarContentDividerAfter value optional. Toolbar item identifier after which the content divider appears.
--- @prop toolbarLabels boolean optional. Component-specific setting passed to the native control.
--- @prop transparentTitlebar boolean optional. Uses a transparent title bar when true.
--- @prop visible boolean optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @example <Window title="Example" />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Window(props)
	local scope = Scope.push()
	local title = props.title or "Window"
	local requested_size = props.size
	local has_requested_size = type(requested_size) == "table"
		or type(requested_size) == "userdata"
	local width = (has_requested_size
			and (requested_size.width or requested_size[1]))
		or props.width or 480
	local height = (has_requested_size
			and (requested_size.height or requested_size[2]))
		or props.height or 360
	local has_workspace = props.sidebar ~= nil and props.content ~= nil
	local transparent_titlebar = props.transparentTitlebar
	if transparent_titlebar == nil then
		transparent_titlebar = has_workspace
	end
	local hide_title = props.hideTitle
	if hide_title == nil then hide_title = transparent_titlebar end

	local toolbar = props.toolbar
	local win
	if toolbar then
		for _, item in ipairs(toolbar) do
			if type(item) == "table" and type(item.view) == "userdata" and item.view.className == "NSSearchField" then
				item.type = "search"
			end
		end
		win = bridge._window(title, width, height,
			transparent_titlebar, hide_title, toolbar,
			props.toolbarLabels == true)
		-- Toolbar items may declare their control inline in XML
		-- (<ToolbarItem id="search"><SearchField ... /></ToolbarItem>).
		-- Install it on the native item here so controllers only render
		-- templates, keep refs, and bind actions.
		for _, item in ipairs(toolbar) do
			if type(item) == "table" and type(item.view) == "userdata" then
				local view = item.view
				local nativeItem = bridge._toolbar_item(win, item.id)
				if nativeItem then
					if item.type == "search" then
						nativeItem.searchField = view
						if view.fixedWidth then nativeItem.preferredWidthForSearchField = view.fixedWidth end
					else nativeItem.view = view end
					if item.bordered ~= nil then nativeItem.bordered = item.bordered end
				end
				item.view = nil
			end
		end
	else
		win = bridge._window(title, width, height,
			transparent_titlebar, hide_title)
	end
	win.size = AppKit.Size(width, height)
	if props.minWidth or props.minHeight then
		win.contentMinSize = AppKit.Size(
			props.minWidth or width,
			props.minHeight or height)
	end
	if props.tabbingMode or props.tabbingIdentifier then
		win.tabbing = props.tabbingMode or "automatic"
		win.tabbingIdentifier = props.tabbingIdentifier
	end
	local appearance = props.appearance
		or os.getenv("LUA_OBJC_APPEARANCE")
		or _G._LAUNCH_APPEARANCE
	if appearance == "light" or appearance == "dark" or appearance == "system" then
		win.appearanceStyle = appearance
	end

	if has_workspace then
		bridge._setWindowWorkspace(
			win,
			props.sidebar,
			props.content,
			props.contentAccessory,
			props.sidebarWidth,
			props.toolbarContentDividerAfter,
			props.detail,
			props.detailWidth)
	else
		local content = bridge._vstack()
		win:add(content)
		if props.content then
			if type(props.content) == "userdata" then
				content:add(props.content)
			elseif type(props.content) == "table" then
				addChildren(content, props.content)
			end
		end
		for _, child in ipairs(props) do
			if type(child) == "userdata" then
				content:add(child)
			elseif type(child) == "table" and child.__appkitGroup then
				addChildren(content, child)
			end
		end
		content:layout(width)
	end

	if props.visible ~= false and not _G.__headless then
		bridge._timerAfter(0, function()
			win:show()
		end)
	end
	bridge._onWindowClose(win, function()
		scope:close()
	end)
	return win
end

function AppKit.addTabbedWindow(window, tabbedWindow, order)
	window:addTabbedWindow(tabbedWindow, order or "above")
	return tabbedWindow
end

function AppKit.windowTabCount(window)
	return window:tabCount()
end

function AppKit.selectWindowTab(window)
	window:selectTab()
	return window
end

--- Creates a floating utility panel with native AppKit panel behavior.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop material string optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @example <Panel title="Example" />
--- @platform AppKit uses the AppKit implementation.
function AppKit.Panel(props)
	props = props or {}
	local width = props.width or 480
	local height = props.height or 240
	local panel = bridge._panel(
		width,
		height,
		props.material or "popover")
	local content = bridge._vstack()
	applyLayout(content, props)
	panel:add(content)
	addChildren(content, props)
	content:layout(width)
	return panel, content
end

--- Creates a sheet window for presentation from a parent window.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @example <Sheet title="Example" />
--- @platform AppKit uses the AppKit implementation.
function AppKit.Sheet(props)
	props = props or {}
	local sheet = bridge._sheet(props.width or 480, props.height or 240)
	local content = bridge._vstack()
	applyLayout(content, props)
	sheet:add(content)
	addChildren(content, props)
	content:layout(props.width or 480)
	return sheet
end

function AppKit.presentSheet(sheet, parent)
	if not _G.__headless then sheet:presentSheet(parent) end
	return sheet
end

function AppKit.present(panel, parent, props)
	props = props or {}
	return panel:presentPanel(parent, props.offsetY or 0)
end

function AppKit.dismiss(window)
	return window:dismiss()
end

function AppKit.focus(window, view)
	return window:focus(view)
end

function AppKit.isFirstResponder(window, view)
	return window:isFirstResponder(view)
end

function AppKit.resizeWindow(window, width, height, anchor)
	if anchor and anchor ~= "" then
		return window:resize(width, height, anchor)
	end
	window.size = AppKit.Size(width, height)
end

function AppKit.relayout(view, width)
	return view:layout(width)
end

--- Creates a native menu command with a keyboard equivalent and action.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop keyEquivalent value optional. Keyboard equivalent for the menu command.
--- @prop menu string optional. Menu name that owns this item.
--- @prop modifiers table optional. Keyboard modifiers required with the key equivalent.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation.
function AppKit.MenuItem(props)
	props = props or {}
	local modifiers = props.modifiers or { "command" }
	if type(modifiers) == "table" then
		modifiers = table.concat(modifiers, ",")
	end
	return bridge._menuItem(
		props.menu or "Application",
		props.title or "",
		props.keyEquivalent or "",
		modifiers,
		assert(props.action, "MenuItem requires an action"))
end

-- #Preview equivalent: renders a named preview in the IDE canvas.
-- In a real window context it behaves like Window; in canvas eval the
-- bridge intercepts it the same way it intercepts Window.
--- Creates a fixed-size preview root for the IDE canvas.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @example <Preview />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Preview(props)
	props = props or {}
	local width  = props.width  or 393   -- iPhone 16 logical width
	local height = props.height or 852   -- iPhone 16 logical height
	local content_fn = props.content
	local root = bridge._vstack()
	root.fixedWidth  = width
	root.fixedHeight = height
	if content_fn then
		local child = content_fn()
		if type(child) == "userdata" then
			root:add(child)
		end
	else
		-- allow inline children: ns.Preview { ns.Text "hi" }
		addChildren(root, props)
	end
	root:layout(width)
	return root
end

--- Presents mutually exclusive content in native tabs.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop selected table optional. Selected option, tab, or row identifier.
--- @prop style string optional. Component-specific setting passed to the native control.
--- @prop tabs table optional. Tab definitions containing a title and content.
--- @example <TabView />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.TabView(props)
	local style = props and props.style or "top"
	local tv = bridge._tabview(400, 200, style)
	local tabs = props and props.tabs or {}
	for _, tab in ipairs(tabs) do
		if type(tab) == "table" and tab.__tab then
			local content = tab.content
			if type(content) == "table" then
				content = AppKit.VStack(content)
			end
			tv:addTab(tab.title or "", content)
		end
	end
	if props and props.selected ~= nil then
		tv:selectTab(props.selected)
	end
	if props and type(props.onChange) == "function" then
		tv:onChange(props.onChange)
	end
	return applyLayout(tv, props)
end

--- A view that arranges its subviews in a vertical line.
---
--- Children in the array part stack top-to-bottom with 8pt sibling
--- spacing and no implicit outer padding. Set `padding` explicitly when
--- the group needs margins. Hidden children consume no space and add no
--- spacing.
--- @tag VStack
--- @prop spacing number optional. Sibling spacing in points.
--- @prop padding number optional. Explicit outer margins.
--- @prop alignment string optional. Cross-axis alignment.
--- @prop fillWidth boolean optional. Expand to the parent width.
--- @prop fillHeight boolean optional. Expand to the parent height.
--- @platform AppKit NSView (vertical layout). UIKit UIView (vertical layout).
--- @example <VStack><Label>Line 1</Label><Label>Line 2</Label></VStack>
--- @see HStack, ZStack, FlowStack, Spacer
function AppKit.VStack(props)
	local view = bridge._vstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

--- Arranges child views horizontally with sibling spacing.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <HStack />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.HStack(props)
	local view = bridge._hstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

--- Wraps child views into additional rows or columns as space runs out.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <FlowStack />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.FlowStack(props)
	local view = bridge._flowStack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

local function stackChildren(props, header)
	local content = {
		spacing = props.spacing or 8,
		alignment = props.alignment or "leading",
	}
	if header and header ~= "" then
		content[#content + 1] = AppKit.Text({ header, weight = "bold" })
	end
	for _, child in ipairs(props) do content[#content + 1] = child end
	return content
end

--- Groups related content and may display a header.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop header table optional. Section or group heading.
--- @example <Section />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Section(props)
	props = props or {}
	return AppKit.VStack(stackChildren(props, props.header))
end

--- Groups related controls inside a titled native box.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop header table optional. Section or group heading.
--- @example <GroupBox />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.GroupBox(props)
	props = props or {}
	local box = bridge._box()
	box.title = props.header or ""
	if not props.header then box.titlePosition = 0 end
	box.contentView = AppKit.VStack(stackChildren(props))
	return applyLayout(box, props)
end

--- Arranges controls as a settings or data-entry form.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <Form />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Form(props)
	props = props or {}
	local content = {
		spacing = props.spacing or 12,
		alignment = props.alignment or "leading",
	}
	for _, child in ipairs(props) do content[#content + 1] = child end
	return applyLayout(AppKit.VStack(content), props)
end

--- Pairs a descriptive label with its value or child controls.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop labelWeight value optional. System font weight for the label.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <LabeledContent />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.LabeledContent(props)
	props = props or {}
	local row = { spacing = props.spacing or 12, alignment = "center" }
	if props.label and props.label ~= "" then
		row[#row + 1] = AppKit.Text({ props.label, weight = props.labelWeight })
	end
	for _, child in ipairs(props) do row[#row + 1] = child end
	return applyLayout(AppKit.HStack(row), props)
end

--- Groups related controls into a compact row.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <ControlGroup />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.ControlGroup(props)
	props = props or {}
	local row = { spacing = props.spacing or 8, alignment = props.alignment or "center" }
	for _, child in ipairs(props) do row[#row + 1] = child end
	return applyLayout(AppKit.HStack(row), props)
end

--- Shows a header that expands or collapses its child content.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop expanded boolean optional. Component-specific setting passed to the native control.
--- @prop header table optional. Section or group heading.
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <DisclosureGroup />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.DisclosureGroup(props)
	props = props or {}
	local content = AppKit.VStack({
		spacing = props.spacing or 8,
		alignment = props.alignment or "leading",
	})
	for _, child in ipairs(props) do content:add(child) end
	local container = AppKit.VStack { spacing = 8, alignment = "leading" }
	local expanded = props.expanded ~= false
	local button = AppKit.Button {
		title = props.label or props.header or "Details",
		style = "plain",
		action = function()
			expanded = not expanded
			content.hidden = not expanded
			container:layout()
		end,
	}
	container:add(button)
	container:add(content)
	content.hidden = not expanded
	return applyLayout(container, props)
end

local function outlineItems(ns, items, expanded)
	local views = {}
	for _, item in ipairs(items or {}) do
		local title = item.title or item.name or tostring(item)
		local children = item.children
		if type(children) == "table" and #children > 0 then
			local nested = ns.VStack { spacing = 4, alignment = "leading" }
			for _, child in ipairs(outlineItems(ns, children, expanded)) do
				nested:add(child)
			end
			views[#views + 1] = ns.DisclosureGroup {
				label = title,
				expanded = expanded,
				nested,
			}
		else
			views[#views + 1] = ns.Text(title)
		end
	end
	return views
end

--- Builds a nested disclosure hierarchy from tree data.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop data table optional. Input rows or values consumed by the component.
--- @prop expanded boolean optional. Component-specific setting passed to the native control.
--- @prop items table optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <OutlineGroup />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.OutlineGroup(props)
	props = props or {}
	local data = props.data or props.items or {}
	assert(type(data) == "table", "OutlineGroup requires data or items")
	local content = outlineItems(AppKit, data, props.expanded)
	content.spacing = props.spacing or 4
	content.alignment = props.alignment or "leading"
	return applyLayout(AppKit.VStack(content), props)
end

--- Adds native scrolling around one content view.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop contentHeight number optional. Scroll content height; zero lets the content size itself.
--- @prop contentWidth number optional. Scroll content width; zero lets the content size itself.
--- @prop horizontal boolean optional. Component-specific setting passed to the native control.
--- @prop vertical boolean optional. Component-specific setting passed to the native control.
--- @example <ScrollView />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.ScrollView(props)
	assert(type(props) == "table", "ScrollView requires a property table")
	local content = props.content or props[1]
	assert(type(content) == "userdata", "ScrollView requires one content view")
	local view = bridge._scrollView(
		content,
		props.contentWidth or 0,
		props.contentHeight or 0)
	if props.horizontal then
		view.hasHorizontalScroller = true
	else
		view.hasHorizontalScroller = false
	end
	local vertical = props.vertical
	if vertical == nil then vertical = not props.horizontal end
	if vertical then
		view.hasVerticalScroller = true
	else
		view.hasVerticalScroller = false
	end
	return applyLayout(view, props)
end

--- Places panes side by side in a native split view.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop proportions table optional. Initial split pane proportions; values are normalized by the split view.
--- @example <HSplit />
--- @platform AppKit uses the AppKit implementation.
function AppKit.HSplit(props)
	local view = bridge._hsplit()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
		if props.proportions then
			view:splitProportions(props.proportions)
		end
	end
	return view
end

-- VSplit: NSSplitView splitting top-to-bottom (vertical=NO in AppKit terms).
-- Mirrors Xcode's DVTSplitView used to stack editor + debug area.
--- Places panes vertically in a native split view.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop proportions table optional. Initial split pane proportions; values are normalized by the split view.
--- @example <VSplit />
--- @platform AppKit uses the AppKit implementation.
function AppKit.VSplit(props)
	local view = bridge._vsplit()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
		if props.proportions then
			view:splitProportions(props.proportions)
		end
	end
	return view
end

-- Separator: 1pt NSBox rule, fills available width.
-- Mirrors Xcode's thin dividers between ControlBar areas.
--- Draws a native separator between adjacent content.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <Separator />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Separator(props)
	return applyLayout(bridge._separator(), props)
end

function AppKit.Group(children)
	children = children or {}
	children.__appkitGroup = true
	return children
end

--- Aligns child views into rows and columns.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <Grid />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Grid(props)
	props = props or {}
	local columnWidths = {}
	for _, row in ipairs(props) do
		for column, child in ipairs(row) do
			local size = child.size
			local width = size and size.width or 0
			columnWidths[column] = math.max(columnWidths[column] or 0, width)
		end
	end
	local rows = {}
	for _, row in ipairs(props) do
		local rowProps = { spacing = props.spacing, alignment = props.alignment }
		for column, child in ipairs(row) do
			if columnWidths[column] and columnWidths[column] > 0 then
				child.fixedWidth = columnWidths[column]
			end
			rowProps[#rowProps + 1] = child
		end
		rows[#rows + 1] = AppKit.HStack(rowProps)
	end
	props.content = nil
	for i = #props, 1, -1 do props[i] = nil end
	for _, row in ipairs(rows) do props[#props + 1] = row end
	return AppKit.VStack(props)
end

function AppKit.ForEach(data, content)
	if type(data) ~= "table" then
		error("ForEach requires an array")
	end
	if type(content) ~= "function" then
		error("ForEach requires a content function")
	end
	local views = AppKit.Group {}
	for index, value in ipairs(data) do
		local result = content(value, index, #data)
		if type(result) == "userdata"
			or (type(result) == "table" and result.__appkitGroup) then
			views[#views + 1] = result
		end
	end
	return views
end

--- A view that displays one or more lines of read-only text.
---
--- Accepts a plain string or a table whose first element is the string.
--- Use `size` and `weight` for hierarchy; prefer system typography over
--- hard-coded custom fonts. Long text wraps under the parent width
--- proposal unless `lineLimit` truncates it.
--- @tag Text
--- @prop [1] string required. Label content.
--- @prop size number optional. System font size in points.
--- @prop weight string optional. System font weight (e.g. "bold", "semibold").
--- @prop color string optional. Semantic system color name.
--- @prop alignment string optional. One of "leading", "center", "trailing".
--- @prop lineLimit number optional. Maximum lines; 0 means unlimited.
--- @prop truncation string optional. One of "head", "middle", "tail".
--- @prop wrapping string optional. "word" (default) or "character".
--- @platform AppKit NSTextField (non-editable, bezel-less). UIKit UILabel.
--- @example <Label>Hello</Label>
--- @example <Label size="16" weight="bold">Hello</Label>
--- @see Title, Label, TextField
function AppKit.Text(arg)
	local text, size, weight
	if type(arg) == "table" then
		text = arg[1] or ""
		size = arg.size
		weight = arg.weight
	elseif type(arg) == "string" then
		text = arg
	else
		text = tostring(arg)
	end
	if type(arg) == "table" and arg.systemImage then
		local row = {
			spacing = arg.spacing or 6,
			alignment = "center",
			AppKit.SystemImage({
				name = arg.systemImage,
				accessibilityLabel = arg.accessibilityLabel,
				size = arg.iconSize or arg.size,
				weight = arg.iconWeight or arg.weight,
				color = arg.color,
			}),
			AppKit.Text({ text, size = arg.size, weight = arg.weight,
				italic = arg.italic, color = arg.color,
				lineLimit = arg.lineLimit, truncation = arg.truncation, wrapping = arg.wrapping }),
		}
		return applyLayout(AppKit.HStack(row), arg)
	end

	local v = bridge._label()
	v.text = text
	v.bezeled = false
	v.drawsBackground = false
	v.editable = false
	v.selectable = false
	v.lineLimit = type(arg) == "table" and arg.lineLimit or 0
	v.lineBreakMode = 0

	if size and size > 0 then
		v.font = bridge._font(size, weight, type(arg) == "table" and arg.italic)
	end
	if type(arg) == "table" and arg.color then
		v.textColor = bridge._systemColor(arg.color)
	end
	if type(arg) == "table" and arg.lineLimit then
		v.lineLimit = arg.lineLimit
		if arg.lineLimit > 1 then v.lineBreakMode = 0 end
	end
	if type(arg) == "table" and arg.wrapping then
		v.lineBreakMode = arg.wrapping == "character" and 1 or 0
	end
	if type(arg) == "table" and arg.truncation then
		local modes = { head = 3, tail = 4, middle = 5 }
		v.lineBreakMode = modes[arg.truncation] or 4
	end

	v:sizeToFit()
	local result = applyLayout(v, type(arg) == "table" and arg or nil)
	if type(arg) == "table" and arg.alignment then
		result.textAlignment = ({ leading = 0, center = 2, trailing = 1 })[arg.alignment] or 0
	end
	return result
end

--- Layers child views in the same coordinate area.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <ZStack />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.ZStack(props)
	local view = bridge._zstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

--- Edits a single line of text.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop accessibilityLabel value optional. Component-specific setting passed to the native control.
--- @prop bezeled boolean optional. Shows the native bezel when true.
--- @prop bordered boolean optional. Shows the native border when true.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop drawsBackground boolean optional. Draws the control’s background when true.
--- @prop editable boolean optional. Allows text editing when true.
--- @prop focusRing boolean optional. Shows the native keyboard focus ring when true.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop onCommand function optional. Callback invoked for the corresponding keyboard command.
--- @prop placeholder string optional. Component-specific setting passed to the native control.
--- @prop secure boolean optional. Masks entered text when true.
--- @prop selectable boolean optional. Allows text or rows to be selected when true.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @prop weight value optional. Component-specific setting passed to the native control.
--- @example <TextField />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.TextField(props)
	if type(props) ~= "table" then
		props = { value = tostring(props or "") }
	end
	local field = props.secure and bridge._secureTextField()
		or bridge._textField()
	field.text = props.value or props[1] or ""
	field.placeholder = props.placeholder or ""
	field.editable = props.editable ~= false
	field.selectable = props.selectable ~= false
	field.bezeled = props.bezeled ~= false
	field.bordered = props.bordered ~= false
	field.drawsBackground = props.drawsBackground ~= false
	if props.focusRing == false then field.focusRingType = 1 end
	if props.size then field.font = bridge._font(props.size, props.weight) end
	if props.accessibilityLabel then
		field.accessibilityLabel = props.accessibilityLabel
	end
	bridge._textFieldCallbacks(field, props.onChange, props.onCommand)
	if props.disabled ~= nil then field.enabled = not props.disabled end
	return applyLayout(field, props)
end

-- SwiftUI's searchable modifier maps to AppKit's native NSSearchField on
-- macOS. The control owns its bezel, search icon, clear button, focus ring,
-- keyboard behavior, and capsule geometry.
local search_control_sizes = {
	mini = 2,
	small = 1,
	regular = 0,
	large = 3,
	extraLarge = 4,
}

--- Provides native search input and search-specific behavior.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop accessibilityLabel value optional. Component-specific setting passed to the native control.
--- @prop controlSize string optional. Component-specific setting passed to the native control.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop onCommand function optional. Callback invoked for the corresponding keyboard command.
--- @prop placeholder string optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <SearchField />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.SearchField(props)
	props = props or {}
	local field = bridge._searchField()
	if props.controlSize ~= nil then
		local controlSize = search_control_sizes[props.controlSize]
		assert(controlSize ~= nil, "invalid SearchField controlSize")
		field.controlSize = controlSize
	end
	field.stringValue = props.value or props[1] or ""
	field.placeholderString = props.placeholder or "Search"
	if props.accessibilityLabel then
		field.accessibilityLabel = props.accessibilityLabel
	end
	bridge._textFieldCallbacks(field, props.onChange, props.onCommand)
	return applyLayout(field, props)
end

--- Edits multiline text.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop drawsBackground boolean optional. Draws the control’s background when true.
--- @prop editable boolean optional. Allows text editing when true.
--- @prop language string optional. Component-specific setting passed to the native control.
--- @prop selectable boolean optional. Allows text or rows to be selected when true.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop text string optional. Initial or displayed text value.
--- @prop weight value optional. Component-specific setting passed to the native control.
--- @prop wrapMode string optional. Text wrapping mode.
--- @example <TextEditor />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.TextEditor(props)
	props = props or {}
	local view = bridge._textView()
	local textView = view.documentView
	if props.language then view.language = props.language end
	if props.text then view.text = props.text end
	if props.wrapMode ~= nil then view.wrapMode = props.wrapMode end
	if props.size then
		textView.font = bridge._font(props.size, props.weight)
	end
	if props.editable ~= nil then
		textView.editable = props.editable ~= false
	end
	if props.selectable ~= nil then
		textView.selectable = props.selectable ~= false
	end
	if props.drawsBackground ~= nil then
		textView.drawsBackground = props.drawsBackground ~= false
	end
	if props.wrapMode ~= nil then
		view.hasHorizontalScroller = not props.wrapMode
	end
	return applyLayout(view, props)
end

--- Displays prominent window or section title text.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Title(arg)
	return AppKit.Text({
		type(arg) == "table" and arg[1] or arg,
		size = 22,
		weight = "bold",
	})
end

--- Displays a raster or vector image asset.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop contentMode string optional. Image scaling mode such as fit or fill.
--- @prop fileIcon string optional. Displays a system file icon for the path.
--- @example <Image />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Image(arg)
	local path
	local props
	if type(arg) == "table" then
		path = arg[1] or arg.path or ""
		props = arg
	elseif type(arg) == "string" then
		path = arg
	else
		path = tostring(arg)
	end
	local view = bridge._image(resolveImage(path), nil, props and props.fileIcon or false)
	if props and props.contentMode then view.contentModeName = props.contentMode end
	return applyLayout(view, props)
end

--- Displays an SF Symbol using the platform image system.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <SystemImage />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.SystemImage(arg)
	if type(arg) ~= "table" then
		arg = { tostring(arg) }
	end
	local name = arg.name or arg[1] or ""
	local description = arg.accessibilityLabel or arg.label or name
	local size = arg.size or 17
	local weight = arg.weight or "regular"
	local color = arg.color or "accent"
	local view = bridge._systemImage(name, description, size, weight, color)
	view.badgeColorName = arg.badgeColor
	view.appBundleId = arg.appIcon
	return applyLayout(view, arg)
end

--- Consumes flexible space between neighboring views.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <Spacer />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Spacer(props)
	return applyLayout(bridge._spacer(), props)
end

--- Displays rows of data in a native table or list control.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alternatingRows boolean optional. Alternates row backgrounds when supported by the selected list style.
--- @prop bordered boolean optional. Shows the native border when true.
--- @prop columns table optional. Column descriptors defining the table structure.
--- @prop data table optional. Input rows or values consumed by the component.
--- @prop drawsBackground boolean optional. Draws the control’s background when true.
--- @prop gridLines value optional. Grid line configuration for the table.
--- @prop header table optional. Section or group heading.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop onActivate function optional. Callback invoked when a row or item is activated.
--- @prop onSelect function optional. Callback invoked when row selection changes.
--- @prop refresh function optional. Callback invoked to refresh the displayed data.
--- @prop rowHeight number optional. Requested table row height, in points.
--- @prop style string optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @example <List />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.List(props)
	local columns = props.columns
	if not columns or type(columns) ~= "table" then
		error("List requires a 'columns' property (array of {id, title})")
	end

	local width = props.width or 400
	local height = props.height or 200

	local tv = bridge._tableview(columns, width, height, {
		header = props.header ~= false,
		bordered = props.bordered == true,
		alternatingRows = props.alternatingRows ~= false,
		drawsBackground = props.drawsBackground ~= false,
		gridLines = props.gridLines,
		style = props.style,
	})
	if props.rowHeight then tv.documentView.rowHeight = props.rowHeight end

	if props.data and type(props.data) == "table" then
		tv:replaceRows(props.data)
	end
	if type(props.onSelect) == "function" then
		tv:onRowSelect(props.onSelect)
	end
	if type(props.onActivate) == "function" then
		tv:onRowActivate(props.onActivate)
	end
	if props.reorderable then
		assert(type(props.onReorder) == "function",
			"List reorderable requires an onReorder callback")
		local Difference = require("ui.reorder").Difference
		tv:onRowMove(function(_, from, to)
			local difference = Difference.new()
			difference:move(from, to)
			props.onReorder(difference)
		end)
	end

	if props.refresh and type(props.refresh) == "function" then
		local refresh_fn = props.refresh
		tv:onRefresh(function(list, on_done)
			if not list then return end
			list:showLoading()
			list:clearRows()
			local co = coroutine.create(function()
				local ok, err = pcall(refresh_fn, list)
				if not ok then
					io.stderr:write("refresh error: " .. tostring(err) .. "\n")
				end
				list:hideLoading()
				if on_done then on_done() end
			end)
			resumeCoroutine(co)
		end)
	end

	return applyLayout(tv, props)
end

function AppKit.readDirectory(path, depth)
	return bridge._listDirectory(path, depth or 0)
end

--- Displays hierarchical rows in a native outline control.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alternatingRows boolean optional. Alternates row backgrounds when supported by the selected list style.
--- @prop bordered boolean optional. Shows the native border when true.
--- @prop columns table optional. Column descriptors defining the table structure.
--- @prop data table optional. Input rows or values consumed by the component.
--- @prop drawsBackground boolean optional. Draws the control’s background when true.
--- @prop gridLines value optional. Grid line configuration for the table.
--- @prop header table optional. Section or group heading.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop indentation number optional. Indentation per outline depth, in points.
--- @prop onActivate function optional. Callback invoked when a row or item is activated.
--- @prop onSelect function optional. Callback invoked when row selection changes.
--- @prop rowHeight number optional. Requested table row height, in points.
--- @prop style string optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @example <OutlineView />
--- @platform AppKit uses the AppKit implementation.
function AppKit.OutlineView(props)
	local columns = props.columns
	if not columns or type(columns) ~= "table" then
		error("OutlineView requires a 'columns' property (array of {id, title})")
	end

	local width = props.width or 400
	local height = props.height or 200

	local tv = bridge._outlineview(columns, width, height, {
		header = props.header ~= false,
		bordered = props.bordered == true,
		alternatingRows = props.alternatingRows ~= false,
		drawsBackground = props.drawsBackground ~= false,
		gridLines = props.gridLines,
		style = props.style,
	})

	if props.rowHeight then tv.documentView.rowHeight = props.rowHeight end
	if props.indentation then
		tv.documentView.indentationPerLevel = props.indentation
	end
	if props.data and type(props.data) == "table" then
		tv:replaceRows(props.data)
	end
	if type(props.onSelect) == "function" then
		tv:onRowSelect(props.onSelect)
	end
	if type(props.onActivate) == "function" then
		tv:onRowActivate(props.onActivate)
	end

	return applyLayout(tv, props)
end

--- Creates or retrieves an item in a window toolbar.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @platform AppKit uses the AppKit implementation.
function AppKit.ToolbarItem(window, identifier)
	local item = bridge._toolbar_item(window, identifier)
	if not item then
		error("toolbar item not found: " .. tostring(identifier))
	end
	return item
end

--- A push button backed by a native button control.
---
--- The optional `action` callback fires via target-action and receives
--- the sender as its first argument. Make the most likely safe action
--- primary; never make a destructive action primary. Prefer `Link` for
--- navigation and `Toggle` for on/off state.
--- @tag Button
--- @prop title string required. Button label. Use a precise verb.
--- @prop action function optional. Called with sender: `function(btn) ... end`.
--- @prop style string optional. "plain", "link", "primary", or "row".
--- @prop systemImage string optional. SF Symbol name shown beside the title.
--- @prop size number optional. Title font size; omit for system default.
--- @prop weight string optional. Title font weight.
--- @prop disabled boolean optional. Disables the control when true.
--- @prop accessibilityLabel string optional. VoiceOver label.
--- @platform AppKit NSButton (rounded) or LuaActionButton (compound). UIKit UIButton.
--- @example <Button title="Save" action="save" />
--- @see Link, Toggle, Toolbar
function AppKit.Button(props)
	local title = type(props) == "table" and (props.title or props[1] or "") or ""
	local action = type(props) == "table" and props.action or nil
	local button
	local compound = type(props) == "table"
		and (props.subtitle or props.detail
			or props.style == "primary" or props.style == "row")
	if compound then
		button = bridge._actionButton(
			title,
			props.subtitle or "",
			props.systemImage or "",
			props.style or "plain",
			props.detail or "",
			action)
	elseif action then
		button = bridge._button(title, action)
	else
		button = bridge._button(title)
	end
	if type(props) == "table" then
		if props.size then
			button.font = bridge._font(props.size, props.weight)
			if compound then button.titleLabel.font = button.font end
			button.size = button.fittingSize
		end
		if not compound and (props.style == "plain" or props.style == "link") then
			button.bordered = false
		end
		if not compound and props.systemImage then
			button.image = AppKit.SystemImage { props.systemImage }.image
			button.imagePosition = title == "" and 1 or 2
		end
		if props.accessibilityLabel then button.accessibilityLabel = props.accessibilityLabel end
	end
	if type(props) == "table" and props.disabled ~= nil then
		button.enabled = not props.disabled
	end
	if type(props) == "table" and props.style == "glass" then
		button = bridge._glassEffect(button, "regular", props.cornerRadius or 0)
	end
	return applyLayout(button, props)
end

--- Embeds a view in the current system glass effect.
--- @tag GlassEffect
--- @prop content value required. The view rendered inside the glass effect.
--- @prop style string optional. `regular` or `clear`.
--- @prop cornerRadius number optional. Native glass corner curvature.
--- @example <GlassEffect style="regular"><VStack>...</VStack></GlassEffect>
--- @platform AppKit NSGlassEffectView (macOS 26+).
function AppKit.GlassEffect(props)
	props = props or {}
	local content = props.content or props[1]
	assert(content, "GlassEffect requires content")
	return applyLayout(bridge._glassEffect(content, props.style or "regular",
		props.cornerRadius or 0), props)
end

--- Displays a native WKWebView and optionally binds it to a WebPage.
--- @tag WebView
--- @prop page table optional. Observable `ui.webpage` state object.
--- @prop url string optional. Initial URL when no page object is supplied.
--- @example <WebView page="page" />
--- @platform AppKit WKWebView.
function AppKit.WebView(props)
	props = props or {}
	local page = props.page
	local url = props.url or (page and page.url) or "about:blank"
	local weakPage = setmetatable({ page }, { __mode = "v" })
	local view = bridge._webView(url, function(event, value)
		local target = weakPage[1]
		if target then target:_nativeEvent(event, value) end
	end)
	view.allowsBackForwardNavigationGestures = props.allowsBackForwardNavigation ~= false
	if props.contentBackground == "hidden" then view.underPageBackgroundColor = bridge._systemColor("clear") end
	if page then page:_attachNative(view, bridge._webViewAction) end
	return applyLayout(view, props)
end

--- Opens or navigates to a destination when activated.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @prop url string optional. Component-specific setting passed to the native control.
--- @example <Link />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Link(props)
	props = props or {}
	assert(props.url, "Link requires a URL")
	return applyLayout(bridge._link(props.title or props.label or props[1] or props.url,
		props.url), props)
end

--- Presents a native empty, unavailable, or no-results state.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop description value optional. Secondary explanatory text for an unavailable state.
--- @prop imageSize number optional. Symbol or image size in points.
--- @prop lines number optional. Maximum number of visible text lines.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @prop systemImage string optional. Component-specific setting passed to the native control.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.ContentUnavailable(props)
	props = props or {}
	local content = { spacing = props.spacing or 8, alignment = "center" }
	if props.systemImage then
		content[#content + 1] = AppKit.SystemImage {
			props.systemImage,
			size = props.imageSize or 28,
			color = "secondary",
			accessibilityLabel = props.title or "",
		}
	end
	if props.title then content[#content + 1] = AppKit.Title(props.title) end
	if props.description then
		content[#content + 1] = AppKit.Text {
			props.description,
			alignment = "center",
			color = "secondary",
			lineLimit = props.lines or 0,
		}
	end
	return applyLayout(AppKit.VStack(content), props)
end

AppKit.ActionButton = AppKit.Button

--- Represents an on/off value with a native switch or checkbox.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop is_on value optional. Current on/off value (legacy spelling).
--- @prop label value optional. Component-specific setting passed to the native control.
--- @example <Toggle />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Toggle(props)
	local label = type(props) == "table" and (props.label or props[1] or "") or ""
	local is_on = type(props) == "table" and props.is_on or false
	local action = type(props) == "table" and props.action or nil
	local toggle
	if action then
		toggle = bridge._toggle(label, is_on, action)
	else
		toggle = bridge._toggle(label, is_on)
	end
	if type(props) == "table" and props.disabled ~= nil then toggle.enabled = not props.disabled end
	return applyLayout(toggle, props)
end

--- Selects a numeric value within a continuous range.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop allowsTickMarkValuesOnly boolean optional. Restricts slider values to tick marks when true.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop max number optional. Component-specific setting passed to the native control.
--- @prop min number optional. Component-specific setting passed to the native control.
--- @prop tickMarks table optional. Slider tick mark positions.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <Slider />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Slider(props)
	props = props or {}
	local slider = bridge._slider(
		props.min or 0,
		props.max or 1,
		props.value or props.min or 0,
		props.action)
	if props.tickMarks then slider.numberOfTickMarks = props.tickMarks end
	if props.allowsTickMarkValuesOnly then
		slider.allowsTickMarkValuesOnly = true
	end
	if props.disabled ~= nil then slider.enabled = not props.disabled end
	return applyLayout(slider, props)
end

--- Increments or decrements a numeric value.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop autorepeat boolean optional. Repeats stepper actions while the user holds a step button.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop increment number optional. Component-specific setting passed to the native control.
--- @prop max number optional. Component-specific setting passed to the native control.
--- @prop min number optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @prop wraps boolean optional. Component-specific setting passed to the native control.
--- @example <Stepper />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Stepper(props)
	props = props or {}
	local stepper = bridge._stepper(
		props.min or 0,
		props.max or 100,
		props.increment or 1,
		props.value or props.min or 0,
		props.action)
	if props.wraps then stepper.valueWraps = true end
	if props.autorepeat == false then stepper.autorepeat = false end
	if props.disabled ~= nil then stepper.enabled = not props.disabled end
	return applyLayout(stepper, props)
end

--- Selects one value from a set of options.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop options table optional. Selectable options or menu entries.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <Picker />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Picker(props)
	assert(type(props) == "table", "Picker requires a property table")
	assert(type(props.options) == "table", "Picker requires an options array")
	local picker = bridge._picker(
		props.options,
		props.value or 0,
		props.action)
	if props.disabled ~= nil then picker.enabled = not props.disabled end
	return applyLayout(picker, props)
end

--- Selects a date or time value.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop time value optional. Whether the date picker includes time selection.
--- @prop timestamp number optional. Date value represented as a Unix timestamp.
--- @example <DatePicker />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.DatePicker(props)
	props = props or {}
	local picker = bridge._datePicker(props.timestamp or props.time, props.onChange)
	if props.disabled ~= nil then picker.enabled = not props.disabled end
	return applyLayout(picker, props)
end

--- Selects a color using the platform color control.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop color color optional. Component-specific setting passed to the native control.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @example <ColorPicker />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.ColorPicker(props)
	props = props or {}
	local picker = bridge._colorPicker(props.color, props.onChange)
	if props.disabled ~= nil then picker.enabled = not props.disabled end
	return applyLayout(picker, props)
end

--- Draws a native separator between adjacent content.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <Separator />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Separator(props)
	local v = bridge._box()
	v.boxType = 2
	v.fixedHeight = 1
	v.fillWidth = true
	return applyLayout(v, props)
end

--- Draws a horizontal or vertical native divider.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop orientation string optional. Component-specific setting passed to the native control.
--- @example <Divider />
--- @platform AppKit uses the AppKit implementation.
function AppKit.Divider(props)
	props = props or {}
	local v = bridge._box()
	v.boxType = 2
	if props.orientation == "vertical" then
		v.fixedWidth = 1
		v.fillHeight = true
	else
		v.fixedHeight = 1
		v.fillWidth = true
	end
	return applyLayout(v, props)
end

--- Shows determinate or indeterminate progress.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop indeterminate boolean optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <ProgressView />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.ProgressView(props)
	props = props or {}
	local v = bridge._progressIndicator()
	v.indeterminate = props.indeterminate == true or props.value == nil
	v.style = props.value ~= nil and 0 or 1
	v.displayedWhenStopped = props.value ~= nil
	v.minValue = 0; v.maxValue = 1
	if props.value ~= nil then v.doubleValue = math.max(0, math.min(1, props.value)) end
	return applyLayout(v, props)
end

--- Displays a filesystem path as a navigable or inspectable view.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop fillColor color optional. Component-specific setting passed to the native control.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop lineWidth number optional. Stroke width in points.
--- @prop strokeColor color optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation.
function AppKit.PathView(props)
	props = props or {}
	local w = props.width or 100
	local h = props.height or 100
	local v = bridge._pathView(w, h)
	if props.strokeColor then
		local c = props.strokeColor
		v:setStrokeColor(c[1], c[2], c[3], c[4] or 1)
	end
	if props.fillColor then
		local c = props.fillColor
		v:setFillColor(c[1], c[2], c[3], c[4] or 1)
	end
	if props.lineWidth then
		v:setLineWidth(props.lineWidth)
	end
	return applyLayout(v, props)
end

--- Renders a data-driven curve in a native drawing surface.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop chartPadding number optional. Inset around the plotted data, in points.
--- @prop data table optional. Input rows or values consumed by the component.
--- @prop fallbackMessage string optional. Message shown when no chart data can be rendered.
--- @prop fillArea boolean optional. Fills the area under the plotted curve.
--- @prop fillColor color optional. Component-specific setting passed to the native control.
--- @prop fillWidth boolean optional. Component-specific setting passed to the native control.
--- @prop fixedHeight value optional. Component-specific setting passed to the native control.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop lineWidth number optional. Stroke width in points.
--- @prop strokeColor color optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation.
function AppKit.Curve(props)
	props = props or {}
	local raw = props.data or {}
	local data = {}
	for _, v in ipairs(raw) do
		if v ~= nil then
			data[#data + 1] = v
		end
	end
	if #data < 2 then
		local msg = props.fallbackMessage or "There may be a problem with the server or network."
		return AppKit.VStack {
			fixedHeight = props.fixedHeight or props.height or 100,
			fillWidth = props.fillWidth,
			alignment = "center",
			AppKit.Spacer {},
			AppKit.Text { "Chart Unavailable", size = 15, weight = "bold",
				color = "secondary" },
			AppKit.Text { msg, size = 12, color = "secondary" },
			AppKit.Spacer {},
		}
	end
	local minY, maxY = data[1], data[1]
	for _, v in ipairs(data) do
		if v < minY then minY = v end
		if v > maxY then maxY = v end
	end
	local range = maxY - minY
	if range == 0 then range = 1 end
	local v = AppKit.PathView(props)
	v.scalesToFit = true
	local fillArea = props.fillArea
	local fillColor = props.fillColor
	local lineWidth = props.lineWidth or 2
	v:setLineWidth(lineWidth)
	if props.strokeColor then
		local c = props.strokeColor
		v:setStrokeColor(c[1], c[2], c[3], c[4] or 1)
	end
	local w = props.width or 100
	local h = props.height or 100
	local padding = props.chartPadding or 0
	local drawW = w - padding * 2
	local drawH = h - padding * 2
	local step = #data > 1 and (drawW / (#data - 1)) or 0
	local function cx(i)
		return padding + (i - 1) * step
	end
	local function cy(val)
		return padding + drawH * (1 - (val - minY) / range)
	end
	local firstX, firstY = cx(1), cy(data[1])
	v:moveTo(firstX, firstY)
	for i = 2, #data do
		v:lineTo(cx(i), cy(data[i]))
	end
	if fillArea then
		local lastX = cx(#data)
		local bottom = padding + drawH
		v:lineTo(lastX, bottom)
		v:lineTo(firstX, bottom)
		v:closePath()
		if fillColor then
			v:setFillColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 0.3)
		elseif props.strokeColor then
			local c = props.strokeColor
			v:setFillColor(c[1], c[2], c[3], 0.15)
		end
	end
	return v
end

function AppKit.Layout(view, props)
	if type(view) ~= "userdata" then
		error("Layout requires a view userdata")
	end
	return applyLayout(view, props)
end

function AppKit.ProgressStart(progress)
	progress:start()
end

function AppKit.ProgressStop(progress)
	progress:stop()
end

function AppKit.ToolbarProgress(window, identifier)
	local item = AppKit.ToolbarItem(window, identifier)
	local restore_view = item.view
	local progress = AppKit.ProgressView()
	progress.size = AppKit.Size(32, 32)

	return {
		start = function(self, tooltip)
			if tooltip then item.toolTip = tooltip end
			item.view = progress
			AppKit.ProgressStart(progress)
		end,
		stop = function(self, tooltip)
			AppKit.ProgressStop(progress)
			item.view = restore_view
			item.enabled = true
			if tooltip then item.toolTip = tooltip end
		end,
	}
end

AppKit.Spinner = AppKit.ProgressView
AppKit.SpinnerStart = AppKit.ProgressStart
AppKit.SpinnerStop = AppKit.ProgressStop

function AppKit.sleep(seconds)
	local co = coroutine.running()
	if not co then
		error("sleep() must be called from within a coroutine (use async())")
	end
	bridge._timerAfter(seconds, function()
		resumeCoroutine(co)
	end)
	coroutine.yield()
end

function AppKit.async(fn)
	local co = coroutine.create(fn)
	resumeCoroutine(co)
end

function AppKit.fetch(url)
	local co = coroutine.running()
	if not co then
		error("fetch() must be called from within a coroutine (use async())")
	end
	local body, err = nil, nil
	bridge._httpGet(url, function(b, e)
		body, err = b, e
		resumeCoroutine(co)
	end)
	coroutine.yield()
	if err then error(err) end
	return body
end

function AppKit.json_parse(str)
	local obj, err = bridge._jsonParse(str)
	if err then error(err) end
	return obj
end

function AppKit.fetch_json(url)
	local body = AppKit.fetch(url)
	return AppKit.json_parse(body)
end

function AppKit.HostingController(view)
	return bridge._hostingController(view)
end

-- Per-screen scopes. Each pushed screen gets its own Scope; popping closes
-- it so the popped screen's callbacks do not live until window close.
-- Builder runs inside the new scope so content constructed there binds to
-- the screen, not the window.
local navScreenScopes = setmetatable({}, { __mode = "k" })

--- Manages a stack of screens and navigation transitions.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.NavigationStack(props)
	props = props or {}
	local root = AppKit.HostingController(props.content or props[1])
	root.title = props.title or ""
	local host = applyLayout(bridge._navigationStack(root), props)
	navScreenScopes[host] = {}
	return host
end

function AppKit.pushScreen(nav, title, builder)
	assert(nav ~= nil, "pushScreen requires a navigation stack")
	assert(type(builder) == "function", "pushScreen requires a builder function")
	local stack = navScreenScopes[nav]
	assert(stack ~= nil, "pushScreen requires a NavigationStack host")
	local screenScope = Scope.push()
	local ok, vc = pcall(builder)
	if not ok then
		screenScope:close()
		error(vc, 2)
	end
	if type(vc) ~= "userdata" then
		screenScope:close()
		error("pushScreen builder must return a view or HostingController", 2)
	end
	-- Auto-host plain views; HostingControllers pass through.
	local okHost, hosted = pcall(AppKit.HostingController, vc)
	if okHost then vc = hosted end
	nav:push(vc, title or "")
	table.insert(stack, screenScope)
	return vc
end

function AppKit.popScreen(nav)
	assert(nav ~= nil, "popScreen requires a navigation stack")
	local stack = navScreenScopes[nav]
	assert(stack ~= nil, "popScreen requires a NavigationStack host")
	nav:pop()
	local screenScope = table.remove(stack)
	if screenScope then screenScope:close() end
end

function AppKit.revealInFinder(path)
	bridge._revealInFinder(path)
end

function AppKit.openPath(path)
	return bridge._openPath(path)
end

function AppKit.moveToTrash(path)
	return bridge._moveToTrash(path)
end

function AppKit.copyToClipboard(text)
	bridge._clipboardCopy(text)
end

--- Presents a native alert and returns the selected response.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop buttons table optional. Alert button titles, in display order.
--- @prop message string optional. Explanatory message shown in an alert.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @example <Alert title="Example" />
--- @platform AppKit uses the AppKit implementation.
function AppKit.Alert(props)
	props = props or {}
	return bridge._alert(
		props.title or "",
		props.message or "",
		props.buttons or { "OK" })
end

function AppKit.diskSpace(path)
	return bridge._diskSpace(path)
end

return AppKit
