-- AppKitNative is supplied by the host runtime. Keeping it private lets the
-- public AppKit module remain a single dylib with a stable declarative API.
local bridge = require("AppKitNative")

-- XML-generated native exports are the public module. Lua only adds compound
-- declarative components whose behavior cannot be expressed as a native class
-- declaration.
local AppKit = bridge
AppKit.platform = "AppKit"
local Scope = require("ui.scope")(bridge)
AppKit.Scope = Scope
local commands = require("ui.commands")

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
	"maxRows",
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
	"containerRelativeWidth",
	"fillHeight",
	"fixedSize",
	"ignoresSafeArea",
	"hidden",
	"allowsHitTesting",
	"background",
	"cornerRadius",
	"clipsToBounds",
	"opacity",
	"scaleEffect",
	"rotationEffect",
	"offsetX",
	"offsetY",
	"onClick",
	"onTap",
	"onDrag",
	"onDoubleClick",
	"contextMenu",
	"hoverTooltip",
	"help",
	"onDrop",
}

local function applyLayout(view, props)
	if type(props) ~= "table" then return view end
	for _, key in ipairs(layout_properties) do
		if props[key] ~= nil then
			if key == "background" then
				view.backgroundColor = bridge._systemColor(props[key])
			elseif key == "onClick" or key == "onTap" then
				bridge._addClick(view, props[key])
			elseif key == "onDrag" then
				bridge._addDrag(view, props[key])
			elseif key == "onDoubleClick" then
				bridge._addDoubleClick(view, props[key])
			elseif key == "contextMenu" then
				bridge._addContextMenu(view, props[key])
			elseif key == "hoverTooltip" then
				local tt = props[key]
				bridge._addHoverTooltip(view, tt.title or "", tt.detail or "")
			elseif key == "onDrop" then
				-- SwiftUI `.dropDestination`: files dropped on the stack.
				-- `dropExternalOnly` takes only drags from other apps,
				-- such as the Finder, never this app's own rows.
				-- `onFileDragChanged(targeted)` observes file drags, including
				-- internal drags refused by an external-only destination.
				bridge._setDropHandler(view, props[key], props.dropExternalOnly == true, props.onFileDragChanged)
			elseif key == "help" then
				-- SwiftUI `.help(_:)` is the view's native AppKit tooltip.
				view.toolTip = props[key]
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
--- @prop commands table optional. Application menu bar from `<Commands>` (SwiftUI `.commands`): `appName`, `CommandGroup` edits, `CommandMenu` menus and Help search topics.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop contentAccessory table optional. Accessory view attached to the window content area.
--- @prop detail table optional. Rendered detail pane view.
--- @prop detailWidth number optional. Requested width of the detail pane, in points.
--- @prop contentWidth number optional. Width of the content column between the sidebar and a flexible detail pane, in points.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop hideTitle boolean optional. Component-specific setting passed to the native control.
--- @prop minHeight number optional. Component-specific setting passed to the native control.
--- @prop minWidth number optional. Component-specific setting passed to the native control.
--- @prop sidebar table optional. Rendered navigation sidebar view.
--- @prop sidebarWidth number optional. Component-specific setting passed to the native control.
--- @prop subtitle string optional. Secondary window title (SwiftUI `.navigationSubtitle`); assign `window.subtitle` to update it.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop tabbingIdentifier string optional. Identifier used to group tabbing windows.
--- @prop tabbingMode string optional. Window tabbing mode.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @prop toolbar table optional. Toolbar item descriptors.
--- @prop level string optional. `floating` keeps the window above others and on every Space (SwiftUI `.windowLevel(.floating)`), as a Picture in Picture or mini player window.
--- @prop aspectRatio number optional. Content width over height kept while the user resizes.
--- @prop onClose function optional. Called when the window closes.
--- @prop onBack function optional. The mouse's back button or a swipe right navigates back.
--- @prop onForward function optional. The mouse's forward button or a swipe left navigates forward.
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

	-- The menu bar belongs to the app, not the window: the first window
	-- installs the standard menus under the app's name, and a window that
	-- declares `commands` (SwiftUI `.commands` on its scene) replaces them.
	if props.commands or not AppKit._commandsInstalled then
		AppKit.setCommands(props.commands)
	end

	local toolbar = props.toolbar
	local win
	if toolbar then
		win = bridge._window(title, width, height,
			transparent_titlebar, hide_title, toolbar,
			props.toolbarLabels == true)
	else
		win = bridge._window(title, width, height,
			transparent_titlebar, hide_title)
	end
	win.size = AppKit.Size(width, height)
	-- SwiftUI `.navigationSubtitle`: AppKit draws it beneath the window title.
	if props.subtitle then win.subtitle = props.subtitle end
	if props.minWidth or props.minHeight then
		win.contentMinSize = AppKit.Size(
			props.minWidth or width,
			props.minHeight or height)
	end
	if props.level then win.windowLevel = props.level end
	if props.aspectRatio then win.aspectRatio = props.aspectRatio end
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
			props.detailWidth,
			props.contentWidth)
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
	-- The mouse's back and forward buttons and two-finger horizontal swipes
	-- navigate history, as in Finder and Safari.
	if props.onBack or props.onForward then
		bridge._onNavigationGesture(win, props.onBack, props.onForward)
	end
	local onClose = props.onClose
	bridge._onWindowClose(win, function()
		if onClose then onClose() end
		scope:close()
	end)
	return win
end

--- Installs the application menu bar from a `<Commands>` spec: standard
--- macOS menus named after the app, `CommandGroup` edits and `CommandMenu`
--- additions, plus topics offered by the Help menu's search field.
function AppKit.setCommands(spec)
	local built = commands.build(spec)
	bridge._setMainMenu(built.appName, built.menus, built.helpTopics)
	AppKit._commandsInstalled = true
	return built
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

-- A sheet owns the callbacks created while it is built. Presenting from a
-- builder scopes those closures to the sheet and releases them on dismiss,
-- so controllers never manage a Scope. UIKit.presentSheet shares this
-- signature; `parent` is the AppKit window the sheet attaches to.
local sheetScopes = setmetatable({}, { __mode = "k" })
local defaultFocusViews = setmetatable({}, { __mode = "k" })

local function buildScoped(contentOrBuilder)
	if type(contentOrBuilder) ~= "function" then
		return nil, table.pack(contentOrBuilder)
	end
	local scope = Scope.new()
	local results = table.pack(pcall(Scope.withScope, scope, contentOrBuilder))
	if not results[1] then
		scope:dispose()
		error(results[2], 3)
	end
	return scope, table.pack(table.unpack(results, 2, results.n))
end

-- SwiftUI `.defaultFocus`: the first marked field inside the window receives
-- keyboard focus when it is presented.
local function applyDefaultFocus(window)
	for view in pairs(defaultFocusViews) do
		-- Weak keys can outlive their native object until collection.
		local ok, owner = pcall(function() return view.window end)
		if not ok then
			defaultFocusViews[view] = nil
		elseif owner == window then
			window:focus(view)
			return
		end
	end
end

--- Resolves a font value for assignment to a text view's `font`.
--- Keys match the XML text attributes: size, weight, italic, design.
function AppKit.Font(props)
	assert(type(props) == "table" and tonumber(props.size), "Font requires a size")
	return bridge._font(props.size, props.weight, props.italic == true, props.design,
		props.monospacedDigit == true, props.fontName, props.smallCaps == true)
end

--- Resolves a semantic name ("primary", "accent") or #RRGGBB hex to a color.
function AppKit.Color(name)
	return bridge._systemColor(name)
end

function AppKit.presentSheet(contentOrBuilder, options)
	options = options or {}
	assert(options.parent, "presentSheet requires options.parent on AppKit")
	local scope, results = buildScoped(contentOrBuilder)
	local sheet = results[1]
	if scope then sheetScopes[sheet] = scope end
	if not _G.__headless then sheet:presentSheet(options.parent) end
	applyDefaultFocus(sheet)
	return table.unpack(results, 1, results.n)
end

--- Shows a window again after `window:hide()`, making it key; like the
--- constructor, headless runs never put a window on screen.
function AppKit.showWindow(window)
	if not _G.__headless then window:show() end
	return window
end

function AppKit.present(panel, parent, props)
	props = props or {}
	return panel:presentPanel(parent, props.offsetY or 0)
end

function AppKit.dismiss(window)
	window:dismiss()
	local scope = sheetScopes[window]
	sheetScopes[window] = nil
	if scope then scope:close() end
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

--- Presents commands in a native pop-up menu.
--- @tag Menu
--- @prop items table required. MenuItem descriptions and actions.
--- @prop title string optional. Menu button label.
--- @prop systemImage string optional. SF Symbol shown on the menu button.
--- @prop imagePath string optional. Image file shown on the menu button.
--- @prop style string optional. `plain` or `glass` button appearance.
--- @prop symbolSize number optional. SF Symbol point size.
--- @platform AppKit NSPopUpButton and NSMenu.
function AppKit.Menu(props)
	props = props or {}
	assert(props.style == nil or props.style == "plain" or props.style == "glass",
		"menu style must be 'plain' or 'glass'")
	local button = bridge._menu(props.items or props.children or {},
		-- SwiftUI labels a symbol-only menu with its image alone.
		props.title or (props.systemImage and "" or "Menu"), props.systemImage or "", props.symbolSize,
		props.imagePath or "")
	if props.accessibilityLabel then button.accessibilityLabel = props.accessibilityLabel end
	if props.style == "glass" then
		-- macOS 26 draws native button bezels in glass. The circular bezel
		-- owns the symbol-only menu's shape, focus ring and pressed state.
		button.bezelStyle = (props.title or "") == "" and (props.systemImage or props.imagePath) and 7 or 1
		button.bordered = true
	end
	return applyLayout(button, props)
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
--- @prop accessory table optional. A `TabAccessory` record: SwiftUI `tabViewBottomAccessory`.
--- @example <TabView />
--- @platform AppKit retains the accessory for its refs without showing it (macOS has no tab-bar accessory). UIKit uses `UITabBarController.bottomAccessory`.
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
	if props and props.accessory then
		tv.accessoryView = props.accessory.content
		tv.accessoryHidden = props.accessory.hidden == true
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

function AppKit.attachReorder(container, children, onReorder)
	assert(type(onReorder) == "function", "reorder container requires an action")
	local Difference = require("ui.reorder").Difference
	bridge._attachReorder(container, children, function(from, to)
		onReorder(Difference.new():move(from, to))
	end)
	return container
end

local function lazyCollection(props, isGrid)
	props = props or {}
	assert(type(props.itemFactory) == "function", "lazy collection requires itemFactory")
	local onMove
	if props.reorderable then
		assert(type(props.onReorder) == "function", "lazy collection requires onReorder")
		local Difference = require("ui.reorder").Difference
		onMove = function(from, to)
			props.onReorder(Difference.new():move(from, to))
		end
	end
	local view = bridge._lazyCollection(props.itemCount or 0, props.columns,
		props.rowHeight, props.spacing, props.itemFactory, onMove, isGrid)
	return applyLayout(view, props)
end

function AppKit.LazyVStack(props)
	return lazyCollection(props, false)
end

function AppKit.LazyVGrid(props)
	return lazyCollection(props, true)
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
		table.insert(content, (AppKit.Text({ header, weight = "bold" })))
	end
	for _, child in ipairs(props) do table.insert(content, child) end
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
	for _, child in ipairs(props) do table.insert(content, child) end
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
		table.insert(row, (AppKit.Text({ props.label, weight = props.labelWeight })))
	end
	for _, child in ipairs(props) do table.insert(row, child) end
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
	for _, child in ipairs(props) do table.insert(row, child) end
	return applyLayout(AppKit.HStack(row), props)
end

--- Shows a header that expands or collapses its child content.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop expanded boolean optional. Component-specific setting passed to the native control.
--- @prop header table optional. Section or group heading.
--- @prop indicatorWidth number optional. Width of a symbol column the disclosure triangle is centered in; the content then starts at the label's edge.
--- @prop indicatorSpacing number optional. Gap between the symbol column and the label, with `indicatorWidth`.
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <DisclosureGroup />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.DisclosureGroup(props)
	props = props or {}
	local DISCLOSURE = { spacing = 4 }
	-- In a list of rows that lead with a symbol, the triangle is one more
	-- symbol: `indicatorWidth` centers it in the rows' symbol column, and the
	-- label and the content start at the rows' text edge.
	local gap = props.indicatorSpacing or DISCLOSURE.spacing
	local content = AppKit.VStack({
		spacing = props.spacing or 8,
		alignment = props.alignment or "leading",
		paddingLeading = props.indicatorWidth and props.indicatorWidth + gap or nil,
	})
	for _, child in ipairs(props) do content:add(child) end
	AppKit.transition(content, "opacity")
	local container = AppKit.VStack { spacing = 8, alignment = "leading" }
	local expanded = props.expanded ~= false
	-- SwiftUI's macOS DisclosureGroup is AppKit's disclosure triangle beside a
	-- clickable label; both toggle the same state.
	local triangle, label
	local function toggle(fromTriangle)
		if fromTriangle then
			expanded = triangle.state == 1
		else
			expanded = not expanded
			triangle.state = expanded and 1 or 0
		end
		-- The reveal animates: the content fades and siblings below slide to
		-- their new frames.
		AppKit.withAnimation(AppKit.Animation.snappy(), function()
			content.hidden = not expanded
		end)
	end
	triangle = AppKit.Button { title = "", action = function() toggle(true) end }
	triangle.bezelStyle = 5 -- NSBezelStyleDisclosure
	triangle.buttonType = 1 -- NSButtonTypePushOnPushOff
	triangle.state = expanded and 1 or 0
	triangle.size = triangle.fittingSize
	triangle.accessibilityLabel = props.label or props.header or "Details"
	label = AppKit.Button {
		title = props.label or props.header or "Details",
		style = "plain",
		weight = props.labelWeight,
		size = props.labelSize or (props.labelWeight and 13 or nil),
		action = function() toggle(false) end,
	}
	local header = { spacing = DISCLOSURE.spacing, alignment = "center", triangle, label }
	if props.indicatorWidth then
		local inset = math.max(0, (props.indicatorWidth - triangle.size.width) / 2)
		header.paddingLeading, header.spacing = inset, inset + gap
	end
	container:add(AppKit.HStack(header))
	container:add(content)
	content.hidden = not expanded
	-- The header row spans the width it is offered, as in SwiftUI.
	container.fillWidth = true
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
			table.insert(views, (ns.DisclosureGroup {
				label = title,
				expanded = expanded,
				nested,
			}))
		else
			table.insert(views, (ns.Text(title)))
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
	if props.scrollOnKeyboard then view.scrollOnKeyboard = true end
	-- scrollDismissesKeyboard has no Mac counterpart: a hardware keyboard is
	-- never on screen, so SwiftUI ignores it on macOS as well.
	-- Trackpad and wheel scrolling on the Mac is continuous; SwiftUI's
	-- scrollTargetBehavior only snaps touch scrolling, so AppKit records it.
	if props.scrollTargetBehavior then view.scrollTargetBehavior = props.scrollTargetBehavior end
	return applyLayout(view, props)
end

--- Pins the second child to a safe-area edge while the first child uses the remaining space.
---
--- The bottom edge is laid out above the containing window's content boundary.
--- @prop edge string optional. Currently `bottom`.
--- @prop minimumBottomInset number optional. Minimum clearance below the accessory.
--- @prop horizontalInset number optional. Horizontal clearance around the accessory.
--- @platform AppKit.
function AppKit.SafeAreaInset(props)
	props = props or {}
	assert(props.edge == nil or props.edge == "bottom", "SafeAreaInset currently supports edge=bottom")
	assert(type(props[1]) == "userdata" and type(props[2]) == "userdata" and props[3] == nil,
		"SafeAreaInset requires content and inset children")
	local accessory = AppKit.VStack {
		spacing = 0, fillWidth = true, paddingHorizontal = props.horizontalInset or 0, props[2],
	}
	local children = { spacing = 0, fillWidth = true, fillHeight = true,
		paddingBottom = props.minimumBottomInset or 0, props[1], accessory }
	return applyLayout(AppKit.VStack(children), props)
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
			table.insert(rowProps, child)
		end
		table.insert(rows, (AppKit.HStack(rowProps)))
	end
	props.content = nil
	for i = #props, 1, -1 do props[i] = nil end
	for _, row in ipairs(rows) do table.insert(props, row) end
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
			table.insert(views, result)
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
--- @prop monospacedDigit boolean optional. Uses fixed-width digits so changing numbers do not shift (SwiftUI `.monospacedDigit()`); requires `size`.
--- @prop minimumScaleFactor number optional. Smallest fraction of `size` the text shrinks to when offered less width (SwiftUI `.minimumScaleFactor`).
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
	-- An empty symbol name is no symbol, so templates can bind it conditionally.
	if type(arg) == "table" and arg.systemImage and arg.systemImage ~= "" then
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
				italic = arg.italic, color = arg.color, design = arg.design,
				monospacedDigit = arg.monospacedDigit, fontName = arg.fontName, smallCaps = arg.smallCaps,
				lineLimit = arg.lineLimit, truncation = arg.truncation, wrapping = arg.wrapping,
				minimumScaleFactor = arg.minimumScaleFactor }),
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
		v.font = bridge._font(size, weight,
			type(arg) == "table" and arg.italic,
			type(arg) == "table" and arg.design,
			type(arg) == "table" and arg.monospacedDigit == true,
			type(arg) == "table" and arg.fontName or nil,
			type(arg) == "table" and arg.smallCaps == true)
	end
	if type(arg) == "table" and arg.color then
		v.textColor = bridge._systemColor(arg.color)
	end
	-- SwiftUI `.minimumScaleFactor`: `size` is the largest size; a narrower
	-- proposal shrinks the font down to `size * minimumScaleFactor`.
	if type(arg) == "table" and arg.minimumScaleFactor then
		v.minimumScaleFactor = arg.minimumScaleFactor
	end
	if type(arg) == "table" and arg.accessibilityLabel then
		v.accessibilityLabel = arg.accessibilityLabel
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
		result.textAlignment = bridge._textAlignment(arg.alignment)
	end
	return result
end


--- Long-form prose set as a book sets it: selectable text with explicit
--- leading, optional hyphenation, and an optional dropped initial that the
--- following lines wrap around. Use `Label` for short text and UI copy.
--- @tag Paragraph
--- @prop text string required. The paragraph's text.
--- @prop size number optional. Body point size; defaults to 13.
--- @prop design string optional. `default`, `serif`, `rounded` or `monospaced`.
--- @prop fontName string optional. An OS-bundled face; falls back to `design`.
--- @prop color string optional. Semantic or hex text colour.
--- @prop lineSpacing number optional. Extra points between lines (SwiftUI `lineSpacing`).
--- @prop alignment string optional. `leading`, `center`, `trailing` or `justified`.
--- @prop hyphenation boolean optional. Hyphenates long words at line ends.
--- @prop figure string optional. Image beside the first lines, which wrap around it (as Zork Zero set a room's picture beside its description).
--- @prop figureLines number optional. Lines the square figure spans; defaults to 3.
--- @prop revealedCharacters number optional. Typewriter reveal: characters shown so far (as `utf8.len` counts them); -1, the default, shows all. Lines are those of the whole text, which takes its whole height however little is revealed.
--- @prop links table optional. Runs the reader can act on, from `<Hyperlink>` children: `{ location, length, label, items }`, where `location` (from 0) and `length` count characters as `utf8.len` does and `items` are `<MenuItem>` records. A link is marked with a thicker dotted underline and opens its menu when tapped.
--- @prop linkColor string optional. Colour of the rule under links; defaults to the tint.
--- @example <Paragraph text="Once upon a time…" design="serif" lineSpacing="5" figure="assets/hall.png" />
--- @platform AppKit non-editable NSTextView (TextKit 1 exclusion paths). UIKit non-scrolling UITextView.
function AppKit.Paragraph(props)
	props = props or {}
	local view = bridge._paragraph(props.text or props[1] or "")
	view.font = bridge._font(props.size or 13, props.weight, props.italic == true, props.design,
		false, props.fontName, props.smallCaps == true)
	if props.color then view.textColor = bridge._systemColor(props.color) end
	if props.lineSpacing then view.lineSpacing = props.lineSpacing end
	if props.hyphenation ~= nil then view.hyphenation = props.hyphenation end
	if props.alignment then view.textAlignment = bridge._textAlignment(props.alignment) end
	if props.selectable == false then view.selectable = false end
	-- The figure is an image view the paragraph floats; it never joins the
	-- layout tree, so the paragraph alone sizes and places it.
	if props.figure and props.figure ~= "" then
		if props.figureLines then view.figureLines = props.figureLines end
		view.figureView = AppKit.Image { props.figure, contentMode = "fill" }
	end
	if props.linkColor then view.linkColor = bridge._systemColor(props.linkColor) end
	if props.links then bridge._paragraphSetLinks(view, props.links) end
	if props.revealedCharacters then view.revealedCharacters = props.revealedCharacters end
	if props.accessibilityLabel then view.accessibilityLabel = props.accessibilityLabel end
	-- Prose fills the column it is given and wraps to it.
	view.fillWidth = true
	return applyLayout(view, props)
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
--- @prop defaultFocus boolean optional. Receives keyboard focus when its sheet is presented (SwiftUI `.defaultFocus`).
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop drawsBackground boolean optional. Draws the control’s background when true.
--- @prop editable boolean optional. Allows text editing when true.
--- @prop focusRing boolean optional. Shows the native keyboard focus ring when true.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop onCommand function optional. Callback invoked for the corresponding keyboard command.
--- @prop onFocus function optional. Callback invoked when editing begins and the keyboard is shown.
--- @prop placeholder string optional. Component-specific setting passed to the native control.
--- @prop style string optional. `plain` removes the field bezel and background; `roundedBorder` keeps the system field bezel.
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
	assert(props.style == nil or props.style == "plain" or props.style == "roundedBorder",
		"TextField style must be 'plain' or 'roundedBorder'")
	local plain = props.style == "plain"
	local field = props.secure and bridge._secureTextField()
		or bridge._textField()
	field.text = props.value or props[1] or ""
	field.placeholder = props.placeholder or ""
	field.editable = props.editable ~= false
	field.selectable = props.selectable ~= false
	field.bezeled = not plain and props.bezeled ~= false
	field.bordered = not plain and props.bordered ~= false
	field.drawsBackground = not plain and props.drawsBackground ~= false
	if props.focusRing == false then field.focusRingType = 1 end
	if props.size then field.font = bridge._font(props.size, props.weight, false, props.design) end
	if props.accessibilityLabel then
		field.accessibilityLabel = props.accessibilityLabel
	end
	bridge._textFieldCallbacks(field, props.onChange, props.onCommand, props.onFocus)
	if props.disabled ~= nil then field.enabled = not props.disabled end
	if props.defaultFocus then defaultFocusViews[field] = true end
	-- SwiftUI text fields accept the available width while keeping native height.
	field.fillWidth = true
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
--- @prop defaultFocus boolean optional. Receives keyboard focus when its sheet is presented (SwiftUI `.defaultFocus`).
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
	bridge._textFieldCallbacks(field, props.onChange, props.onCommand, props.onFocus)
	if props.defaultFocus then defaultFocusViews[field] = true end
	-- Like a TextField, a search field takes the width it is offered.
	field.fillWidth = true
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
		textView.font = bridge._font(props.size, props.weight, false, props.design)
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

--- Displays source in a read-only native text view.
--- @prop language string optional. Syntax language name.
--- @prop size number optional. Monospaced font size.
--- @prop text string required. Source text.
--- @platform AppKit NSTextView with SyntaxTextStorage.
function AppKit.CodeView(props)
	props = props or {}
	return AppKit.TextEditor({ text = props.text or "", language = props.language or "lua",
		editable = false, selectable = true, drawsBackground = props.drawsBackground,
		wrapMode = props.wrapMode, size = props.size, flexGrow = props.flexGrow,
		flexShrink = props.flexShrink, flexBasis = props.flexBasis, maxWidth = props.maxWidth,
		maxHeight = props.maxHeight })
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
	local dark = props and props.darkPath and resolveImage(props.darkPath) or nil
	local view = bridge._image(resolveImage(path), nil, props and props.fileIcon or false, dark)
	if props and props.contentMode then view.contentModeName = props.contentMode end
	if props and props.resizable then
		view.fillWidth, view.fillHeight = true, true
	end
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

-- SwiftUI UnitPoint: x runs leading to trailing, y top to bottom.
local UNIT_POINTS = {
	topLeading = { 0, 0 }, top = { 0.5, 0 }, topTrailing = { 1, 0 },
	leading = { 0, 0.5 }, center = { 0.5, 0.5 }, trailing = { 1, 0.5 },
	bottomLeading = { 0, 1 }, bottom = { 0.5, 1 }, bottomTrailing = { 1, 1 },
}

--- Fills content with a linear gradient, as SwiftUI's LinearGradient.
---
--- With `colors` the gradient runs through those semantic colors, evenly
--- spaced from `startPoint` to `endPoint`, and follows light and dark
--- appearance. Without `colors` it is a vertical black fade for laying text
--- over artwork, shaped by the alpha props.
--- @prop colors table optional. Two or more color names, in order.
--- @prop startPoint string optional. Unit point the first color sits at: `top`, `bottom`, `leading`, `trailing`, `center` or a corner such as `topLeading`. Default `top`.
--- @prop endPoint string optional. Unit point the last color sits at. Default `bottom`.
--- @prop bottomAlpha number optional. Fade opacity at the bottom edge.
--- @prop middleAlpha number optional. Fade opacity at the middle stop.
--- @prop middleLocation number optional. Position of the fade's middle stop, from 0 to 1.
--- @prop topAlpha number optional. Fade opacity at the top edge.
--- @example <LinearGradient colors="systemIndigo,systemPink" startPoint="topLeading" endPoint="bottomTrailing" />
--- @platform AppKit and UIKit.
function AppKit.LinearGradient(props)
	props = props or {}
	local view = bridge._linearGradient(props.topAlpha or 0,
		props.middleAlpha or 0.5, props.middleLocation or 0.6,
		props.bottomAlpha or 0.82)
	if props.colors then
		local start = UNIT_POINTS[props.startPoint or "top"]
		local stop = UNIT_POINTS[props.endPoint or "bottom"]
		assert(start, "LinearGradient startPoint is not a unit point: " .. tostring(props.startPoint))
		assert(stop, "LinearGradient endPoint is not a unit point: " .. tostring(props.endPoint))
		bridge._linearGradientColors(view, props.colors, start[1], start[2], stop[1], stop[2])
	end
	-- Gradients have no intrinsic size and accept both proposed dimensions.
	view.fillWidth, view.fillHeight = true, true
	return applyLayout(view, props)
end

--- Renders a native animated color mesh from a grid of control points.
--- @prop width number required. Number of grid columns.
--- @prop height number required. Number of grid rows.
--- @prop points table optional. Normalized point coordinates in row-major order.
--- @prop colors table optional. Colors in row-major order.
--- @prop animated boolean optional. Animate interior points when true.
--- @platform AppKit and UIKit.
function AppKit.MeshGradient(props)
	props = props or {}
	local width, height = props.width or 3, props.height or 3
	local view = bridge._meshGradient(width, height)
	bridge._meshGradientConfigure(view, width, height, props.points, props.colors,
		props.animated == true)
	view.fillWidth, view.fillHeight = true, true
	return applyLayout(view, props)
end

--- Draws a Metal fragment shader every display frame, like SwiftUI's
--- `TimelineView(.animation)` around a `ShaderLibrary` color effect.
--- The source defines `fragment float4 name(ShaderVertex in [[stage_in]],
--- constant ShaderInputs &inputs [[buffer(0)]])`; `inputs` carries `size`
--- (pixels), `time` (seconds), `count` and `values[256]`. Assign `values`
--- from Lua to animate it. The view is transparent where the shader is.
--- A program can instead be linked from `sources`, `{path = …}` files and
--- `{code = …}` snippets compiled in order as one translation unit, so a
--- shared library, plugin-contributed functions and an entry point can live
--- in separate files. Each chunk opens with a `#line` directive, so compiler
--- errors name the file and line they came from.
---
--- Meshes: with `layers`, the view first renders `draws` into that many
--- offscreen HDR layers (RGBA16Float, cleared to transparent black, with a
--- depth buffer), and `function` finishes the picture from them: layer i is
--- `texture2d<float> [[texture(i - 1)]]`, mipmapped every frame so coarse
--- levels serve as wide blurs. Each draw is a table:
--- `vertex`, `fragment` (function names), `count` (vertices), `instances`
--- (1), `layer` (1), `primitive` (`triangle`, `triangleStrip`, `line`,
--- `lineStrip`, `point`), `blend` (`opaque`, `alpha` premultiplied, `add`),
--- `depth` (`none`, `test`, `write`), `cull` (`none`, `back`, `front`),
--- `data` (floats at `const device float *data [[buffer(1)]]`) and `params`
--- (up to 64 floats at `constant float *params [[buffer(2)]]`). Both stages
--- get `inputs` at buffer(0). Vertices usually come from `vertex_id` and
--- `instance_id`; `fullscreenVertex` covers the view with `ShaderVertex`.
--- Assigning `draws` compiles their pipelines, and a bad list raises
--- without replacing the running one.
--- @prop source string optional. Path of a `.metal` file with the fragment function.
--- @prop sources table optional. `<ShaderSource path="…">` / `<ShaderSource code="…">` chunks, in order.
--- @prop function string required. Fragment function name; with layers, the finishing pass.
--- @prop values table optional. Initial floats for `inputs.values`.
--- @prop layers number optional. Offscreen layers the draws render into, 0…4 (0).
--- @prop draws table optional. Mesh passes, in order (see above).
--- @platform AppKit.
local function readShader(path)
	local file = assert(io.open(path, "r"), "ShaderView: cannot read " .. tostring(path))
	local text = file:read("a")
	file:close()
	return text
end

function AppKit.ShaderView(props)
	props = props or {}
	local text
	if props.sources then
		assert(props.source == nil, "ShaderView takes source or sources, not both")
		local chunks = {}
		for index, chunk in ipairs(props.sources) do
			assert((chunk.path == nil) ~= (chunk.code == nil), "ShaderSource requires exactly one of path or code")
			local name = chunk.path or ("code " .. index)
			table.insert(chunks, string.format('#line 1 "%s"\n%s\n', name, chunk.path and readShader(chunk.path) or chunk.code))
		end
		assert(#chunks > 0, "ShaderView sources is empty")
		text = table.concat(chunks)
	else
		text = readShader(assert(props.source, "ShaderView requires source or sources"))
	end
	local view = bridge._shaderView(text, assert(props["function"], "ShaderView requires function"))
	if props.values then view.values = props.values end
	if props.layers then view.layers = props.layers end
	if props.draws then view.draws = props.draws end
	-- Like a gradient, a shader has no intrinsic size and fills its proposal.
	view.fillWidth, view.fillHeight = true, true
	return applyLayout(view, props)
end

--- Hosts content on the requested update schedule.
--- @prop schedule string optional. `animation` animates a mesh child.
--- @prop content value required. Hosted view.
--- @platform AppKit and UIKit.
function AppKit.TimelineView(props)
	props = props or {}
	local content = props.content or props[1]
	assert(content, "TimelineView requires content")
	if props.schedule == "animation" then content.animated = true end
	return applyLayout(content, props)
end

-- A column's `template` is a Lua factory (see "Column content templates" in
-- docs/tableview_swiftui.md); the native column spec is plain data. Returns
-- the specs without their templates, and a function that installs them.
local function columnTemplates(columns)
	local specs, templates = {}, {}
	for _, column in ipairs(columns) do
		local spec = {}
		for key, value in pairs(column) do
			if key ~= "template" then spec[key] = value end
		end
		if column.template ~= nil then
			assert(type(column.template) == "function", "Column template must be a function")
			assert(column.id, "a Column with a template requires an id")
			templates[column.id] = column.template
		end
		table.insert(specs, spec)
	end
	return specs, function(view)
		for id, template in pairs(templates) do bridge._tableColumnTemplate(view, id, template) end
	end
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
--- @prop onSort function optional. Callback invoked with the column id when a sortable header is clicked.
--- @prop onColumnButton function optional. Callback invoked when a row's column button is clicked.
--- @prop rowMenu function optional. `(list, index, row) -> items` builds the row's context menu (SwiftUI `.contextMenu`) from `{title, action, systemImage, disabled}` and `{separator = true}` records. A column with `buttonMenu` opens the same menu from its row button.
--- @prop scrollDisabled boolean optional. The list does not scroll and is as tall as all its rows (SwiftUI `.scrollDisabled`).
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
	local installTemplates
	columns, installTemplates = columnTemplates(columns)

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
	installTemplates(tv)
	if props.rowHeight then tv.documentView.rowHeight = props.rowHeight end
	if props.scrollDisabled then tv.scrollDisabled = true end

	if props.data and type(props.data) == "table" then
		tv:replaceRows(props.data)
	end
	if type(props.onSelect) == "function" then
		tv:onRowSelect(props.onSelect)
	end
	if type(props.onActivate) == "function" then
		tv:onRowActivate(props.onActivate)
	end
	if type(props.onSort) == "function" then
		tv:onColumnSort(props.onSort)
	end
	if type(props.onColumnButton) == "function" then
		tv:onColumnButton(props.onColumnButton)
	end
	if type(props.rowMenu) == "function" then
		tv:onRowMenu(props.rowMenu)
	end
	-- SwiftUI `.draggable`: rows drag as the file at row[dragKey].
	if props.dragKey then tv:setDragKey(props.dragKey) end
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
	if props.onSwipeLeading then
		tv:onRowSwipe("leading", props.swipeLeadingTitle or "Archive",
			props.swipeLeadingRole or "normal", props.fullSwipe == true,
			function(_, index, row) props.onSwipeLeading(index, row) end)
	end
	if props.onSwipeTrailing then
		tv:onRowSwipe("trailing", props.swipeTrailingTitle or "Delete",
			props.swipeTrailingRole or "destructive", props.fullSwipe == true,
			function(_, index, row) props.onSwipeTrailing(index, row) end)
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

--- A native swipeable table row that can sit inside a VStack or another stack.
--- The table owns swipe chrome, gesture handling, and accessibility.
function AppKit.SwipeRow(props)
	props = props or {}
	local view = AppKit.List {
		columns = { { id = "title", title = "" }, { id = "status", title = "" } },
		data = { { title = props.title or "", status = props.status or "" } },
		header = false,
		alternatingRows = false,
		style = "plain",
		rowHeight = props.rowHeight,
		onSwipeLeading = props.onSwipeLeading and function(_, row)
			props.onSwipeLeading(props.rowId, row)
		end,
		onSwipeTrailing = props.onSwipeTrailing and function(_, row)
			props.onSwipeTrailing(props.rowId, row)
		end,
		swipeLeadingTitle = props.swipeLeadingTitle,
		swipeTrailingTitle = props.swipeTrailingTitle,
		swipeLeadingRole = props.swipeLeadingRole,
		swipeTrailingRole = props.swipeTrailingRole,
		fullSwipe = props.fullSwipe,
	}
	view.fixedHeight = props.rowHeight or view.documentView.rowHeight
	view.hasVerticalScroller = false
	view.hasHorizontalScroller = false
	return applyLayout(view, props)
end

function AppKit.readDirectory(path, depth)
	return bridge._listDirectory(path, depth or 0)
end

function AppKit.readPropertyList(path)
	return bridge._readPropertyList(path)
end

--- Parses property-list text or data, such as `diskutil -plist` output; nil when invalid.
function AppKit.parsePropertyList(text)
	return bridge._parsePropertyList(text)
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
	local installTemplates
	columns, installTemplates = columnTemplates(columns)

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
	installTemplates(tv)

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

local keyboardShortcuts = { defaultAction = "\r", cancelAction = "\27" }

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
--- @prop keyboardShortcut string optional. `defaultAction` (Return) or `cancelAction` (Escape), as SwiftUI `.keyboardShortcut`.
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
	else
		button = bridge._button(title, action, type(props) == "table" and props.content or nil)
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
		-- SwiftUI `.borderedProminent` is AppKit's accent-filled push button;
		-- UIKit maps the same style to its prominent button configuration.
		-- `glassProminent` is the same control on the Mac: macOS 26 draws
		-- prominent push buttons in Liquid Glass. SwiftUI `.tint` fills it.
		if not compound and (props.style == "borderedProminent" or props.style == "glassProminent") then
			button.bezelColor = bridge._systemColor(props.tint or "accent")
		elseif props.tint then
			button.contentTintColor = bridge._systemColor(props.tint)
		end
		if props.controlSize then
			-- SwiftUI `.controlSize`: NSControlSize small, regular, large.
			local sizes = { mini = 2, small = 1, regular = 0, large = 3 }
			button.controlSize = assert(sizes[props.controlSize],
				"Button controlSize must be mini, small, regular or large")
			button.size = button.fittingSize
		end
		if not compound and props.systemImage then
			button.image = AppKit.SystemImage {
				props.systemImage, size = props.symbolSize, weight = props.weight,
			}.image
			button.imagePosition = title == "" and 1 or 2
		end
		if props.foregroundStyle then
			button.contentTintColor = bridge._systemColor(props.foregroundStyle)
		end
		if props.accessibilityLabel then button.accessibilityLabel = props.accessibilityLabel end
		if props.keyboardShortcut then
			-- SwiftUI `.keyboardShortcut(.defaultAction/.cancelAction)`. AppKit
			-- draws a Return-equivalent button as the window's default button.
			local key = keyboardShortcuts[props.keyboardShortcut]
			assert(key, "Button keyboardShortcut must be 'defaultAction' or 'cancelAction'")
			button.keyEquivalent = key
		end
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

--- Groups nearby native glass surfaces into one system effect.
--- @tag GlassEffectContainer
--- @prop content value required. View containing the glass surfaces.
--- @prop spacing number optional. Distance at which neighboring effects begin to merge.
--- @platform AppKit NSGlassEffectContainerView (macOS 26+).
function AppKit.GlassEffectContainer(props)
	props = props or {}
	local content = props.content or props[1]
	assert(content, "GlassEffectContainer requires content")
	return applyLayout(bridge._glassEffectContainer(content, props.spacing or 0), props)
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
	if props.allowsMagnification ~= nil then
		view.allowsMagnification = props.allowsMagnification
	end
	if props.pageZoom then view.pageZoom = props.pageZoom end
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

local UNAVAILABLE = { spacing = 8, imageSize = 28, actionsTop = 8 }

--- Presents a native empty, unavailable, or no-results state.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop children views optional. Action controls shown beneath the message, SwiftUI's `actions:`.
--- @prop description value optional. Secondary explanatory text for an unavailable state.
--- @prop descriptionAlignment string optional. `center` (default), `leading` or `trailing` text alignment of the description.
--- @prop imageSize number optional. Symbol or image size in points.
--- @prop lines number optional. Maximum number of visible text lines.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @prop systemImage string optional. Component-specific setting passed to the native control.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.ContentUnavailable(props)
	props = props or {}
	-- SwiftUI's ContentUnavailableView takes the space it is offered and
	-- centers its message in it. The spacers make the stack flexible along
	-- its main axis, so it fills the parent's height and centers vertically.
	local content = { spacing = props.spacing or UNAVAILABLE.spacing, alignment = "center", AppKit.Spacer() }
	if props.systemImage then
		table.insert(content, (AppKit.SystemImage {
			props.systemImage,
			size = props.imageSize or UNAVAILABLE.imageSize,
			color = "secondary",
			accessibilityLabel = props.title or "",
		}))
	end
	if props.title then table.insert(content, (AppKit.Title(props.title))) end
	if props.description then
		-- The description keeps to the middle half of the pane, a readable
		-- measure like SwiftUI's; the spacers share the other half equally.
		table.insert(content, (AppKit.HStack {
			AppKit.Spacer(),
			AppKit.Text {
				props.description,
				alignment = props.descriptionAlignment or "center",
				flexGrow = 2, flexBasis = 0, flexShrink = 1,
				color = "secondary",
				lineLimit = props.lines or 0,
			},
			AppKit.Spacer(),
			spacing = 0,
			fillWidth = true,
		}))
	end
	-- SwiftUI's `actions:` slot: child controls sit beneath the message and
	-- are centered with it, not pinned to the pane's bottom edge.
	if props[1] then
		local actions = { spacing = UNAVAILABLE.spacing, alignment = "center", paddingTop = UNAVAILABLE.actionsTop }
		for _, action in ipairs(props) do table.insert(actions, action) end
		table.insert(content, (AppKit.VStack(actions)))
	end
	table.insert(content, (AppKit.Spacer()))
	local view = AppKit.VStack(content)
	-- Full width too, so the description's half is half of the pane.
	if props.fillWidth == nil then view.fillWidth = true end
	return applyLayout(view, props)
end

--- Represents an on/off value with a native switch or checkbox.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop is_on value optional. Current on/off value (legacy spelling).
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop tint string optional. Semantic color of the checked state, SwiftUI `.tint`.
--- @prop style string optional. `switch`, or `button` for a push-on/push-off button that fills while on (SwiftUI `.toggleStyle(.button)`).
--- @prop systemImage string optional. SF Symbol shown above a `button` style label.
--- @prop symbolSize number optional. SF Symbol point size; defaults to the label font.
--- @example <Toggle />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Toggle(props)
	local label = type(props) == "table" and (props.label or props[1] or "") or ""
	local is_on = type(props) == "table" and props.is_on or false
	local action = type(props) == "table" and props.action or nil
	local style = type(props) == "table" and props.style or nil
	local toggle
	-- SwiftUI `onChange`: the handler receives the new state.
	if type(props) == "table" and type(props.onChange) == "function" then
		action = function() props.onChange(toggle.state == 1) end
	end
	-- SwiftUI `.tint` is the checked fill. A button-style toggle would tint
	-- its bezel in both states, so it carries the tint only while on and
	-- reads as a lit or unlit pad.
	local tint = type(props) == "table" and props.tint and bridge._systemColor(props.tint) or nil
	local function light()
		if tint then toggle.bezelColor = toggle.state == 1 and tint or nil end
	end
	if style == "button" and tint then
		local changed = action
		action = function(...)
			light()
			if changed then changed(...) end
		end
	end
	if style == "switch" or style == "button" then
		toggle = bridge._toggle(label, is_on, action, style, props.systemImage, props.symbolSize)
	elseif action then
		toggle = bridge._toggle(label, is_on, action)
	else
		toggle = bridge._toggle(label, is_on)
	end
	if type(props) == "table" and props.disabled ~= nil then toggle.enabled = not props.disabled end
	if style == "button" then light() elseif tint then toggle.bezelColor = tint end
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
--- @prop tint string optional. Semantic color filling the track, SwiftUI `.tint`.
--- @prop style string optional. `level` for an editable fill bar (a continuous capacity level indicator).
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <Slider />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Slider(props)
	props = props or {}
	local onChange = props.onChange or props.action
	local callback
	if type(onChange) == "function" then
		-- doubleValue is shared by NSSlider and the level-bar NSLevelIndicator.
		callback = function(slider) onChange(slider.doubleValue) end
	end
	local slider = bridge._slider(
		props.min or 0,
		props.max or 1,
		props.value or props.min or 0,
		callback,
		props.style)
	if props.tickMarks then slider.numberOfTickMarks = props.tickMarks end
	if props.allowsTickMarkValuesOnly then
		slider.allowsTickMarkValuesOnly = true
	end
	if props.disabled ~= nil then slider.enabled = not props.disabled end
	if props.tint then
		-- The track fill for sliders and knobs; the fill for a level bar.
		local color = bridge._systemColor(props.tint)
		if props.style == "level" then slider.fillColor = color else slider.trackFillColor = color end
	end
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
--- @prop style string optional. `menu` (default, NSPopUpButton) or `segmented` (NSSegmentedControl).
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <Picker />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Picker(props)
	assert(type(props) == "table", "Picker requires a property table")
	assert(type(props.options) == "table", "Picker requires an options array")
	local onChange = props.onChange or props.action
	local segmented = props.style == "segmented"
	local callback
	if type(onChange) == "function" then
		callback = function(picker)
			onChange(segmented and picker.selectedSegment or picker.indexOfSelectedItem)
		end
	end
	-- SwiftUI `.pickerStyle(.segmented)` is NSSegmentedControl; the default
	-- menu style is NSPopUpButton. Both report a zero-based index.
	local picker = (segmented and bridge._segmentedPicker or bridge._picker)(
		props.options,
		props.value or 0,
		callback)
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

local progress_control_sizes = { regular = 0, small = 1, mini = 2, large = 3 }

--- Shows determinate or indeterminate progress.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop indeterminate boolean optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @prop controlSize string optional. SwiftUI `.controlSize`: `mini`, `small`, `regular` or `large`.
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
	if props.controlSize ~= nil then
		local controlSize = progress_control_sizes[props.controlSize]
		assert(controlSize ~= nil, "invalid ProgressView controlSize")
		v.controlSize = controlSize
	end
	-- A linear (determinate) ProgressView takes the width it is offered; the
	-- spinner keeps its own size.
	if props.value ~= nil then v.fillWidth = true end
	return applyLayout(v, props)
end

--- Shows a value within a range as a read-only capacity bar.
---
--- SwiftUI `Gauge` with `.linearCapacity`; AppKit uses a continuous-capacity
--- `NSLevelIndicator`, the control Finder and Disk Utility use for storage.
--- @prop value number required. Current value between `minValue` and `maxValue`.
--- @prop minValue number optional. Lower bound, default 0.
--- @prop maxValue number optional. Upper bound, default 1.
--- @prop tint string optional. Semantic fill color.
--- @prop thickness number optional. Draws a capsule bar this many points tall,
--- as SwiftUI's linear capacity Gauge does; omitted, AppKit's own cell.
--- @prop accessibilityLabel string optional. What the gauge measures.
--- @example <Gauge value="0.42" tint="systemBlue" thickness="6" />
--- @platform AppKit NSLevelIndicator. UIKit UIProgressView.
function AppKit.Gauge(props)
	props = props or {}
	local v = bridge._levelIndicator()
	v.minValue = props.minValue or 0
	v.maxValue = props.maxValue or 1
	local value = tonumber(props.value) or v.minValue
	v.doubleValue = math.max(v.minValue, math.min(v.maxValue, value))
	if props.tint then v.fillColor = bridge._systemColor(props.tint) end
	if props.thickness then v.thickness = props.thickness end
	if props.accessibilityLabel then v.accessibilityLabel = props.accessibilityLabel end
	-- A linear Gauge takes the width it is offered, like SwiftUI's.
	v.fillWidth = true
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

--- Draws a circular arc in screen coordinates.
---
--- Angles are degrees, clockwise from east, in a y-down view. Equal angles
--- close the circle. `stroke` is a semantic color name.
--- @prop cornerRadius number optional. Draws the arc as a filled sector of its band with corners rounded this many points.
--- @prop endAngle number optional. Ending angle in degrees.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop lineCap string optional. `butt` or `round`.
--- @prop diameter number optional. With `fitDiameter`, the circle's diameter in units.
--- @prop inset number optional. Draws the arc as a filled sector of its band, every edge moved in by half this many points, so neighbours are this far apart.
--- @prop fitDiameter number optional. Scales the arc to its frame: the frame's shorter side spans this many units, and `diameter` and `lineWidth` are in those units.
--- @prop lineWidth number optional. Stroke width in points.
--- @prop startAngle number optional. Starting angle in degrees.
--- @prop stroke string optional. Semantic stroke color.
--- @prop strokeAlpha number optional. Stroke opacity from 0 to 1.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.Arc(props)
	props = props or {}
	if props.width and not props.fixedWidth then props.fixedWidth = props.width end
	if props.height and not props.fixedHeight then props.fixedHeight = props.height end
	local width = props.fixedWidth or 48
	local height = props.fixedHeight or width
	local view = bridge._arc(width, height)
	view.startAngle = props.startAngle or 0
	view.endAngle = props.endAngle or 0
	if props.lineWidth then view.lineWidth = props.lineWidth end
	if props.stroke then view.stroke = props.stroke end
	if props.strokeAlpha then view.strokeAlpha = props.strokeAlpha end
	if props.lineCap then view.lineCap = props.lineCap end
	if props.diameter then view.diameter = props.diameter end
	if props.fitDiameter then view.fitDiameter = props.fitDiameter end
	if props.inset then view.inset = props.inset end
	if props.cornerRadius then view.cornerRadius = props.cornerRadius end
	return applyLayout(view, props)
end

--- Displays a SceneKit scene described by `Node`, `Camera` and `Light` records.
---
--- Like SwiftUI's `SceneView`, the view fills its proposal. The records form
--- the scene graph and reconcile by `id` when the template renders again:
--- nodes keep their pose and running behaviours, changed attributes apply in
--- place, and `transition` plays when a node is inserted or removed. Game
--- state moves nodes every frame with `view.nodeStates = {{id, x, y, z, yaw,
--- pitch, roll, scale, opacity, hidden}, ...}` (angles in degrees) without
--- describing the scene again.
--- @prop background string optional. Color behind the scene (semantic name or `#rrggbb`).
--- @prop onKey function optional. `onKey(view, key, pressed) -> handled`: presses and releases, never repeats; the view takes the keyboard when it appears.
--- @prop onFrame function optional. `onFrame(view, dt)` once per displayed frame while the view is in a window, `dt` in seconds.
--- @prop onSwipe function optional. `onSwipe(view, direction)` with `left`, `right`, `up` or `down`, sent as soon as a drag (a finger, or the mouse) has travelled far enough.
--- @prop onTap function optional. `onTap(view)` when a press is released without travelling. A drag is one swipe or one tap, never both.
--- @prop showsStatistics boolean optional. Shows SceneKit's frame-rate and draw-call overlay.
--- @example <SceneView background="#8fd3f4"><Camera position="0 6 8" lookAt="0 0 0" /><Light type="directional" rotation="-60 30 0" castsShadow="true" /><Node model="assets/coin.obj" spin="90" /></SceneView>
--- @platform AppKit and UIKit.
function AppKit.SceneView(props)
	props = props or {}
	local records = {}
	for _, child in ipairs(props) do
		if type(child) ~= "table" or not child.sceneKind then
			error("SceneView accepts only Node, Camera and Light records")
		end
		table.insert(records, child)
	end
	local view = bridge._sceneView(props.onKey, props.onFrame, props.onSwipe, props.onTap)
	if props.background then bridge._sceneBackground(view, props.background) end
	if props.showsStatistics then view.showsStatistics = true end
	AppKit.sceneGraph(view, records)
	-- A 3-D viewport has no intrinsic size and fills its proposal.
	view.fillWidth, view.fillHeight = true, true
	local layout = {}
	for key, value in pairs(props) do
		if type(key) ~= "number" and key ~= "onKey" and key ~= "onFrame" and key ~= "onSwipe" and key ~= "onTap" and key ~= "background" then layout[key] = value end
	end
	return applyLayout(view, layout)
end

--- Reconciles a SceneView's graph with new `Node`, `Camera` and `Light` records.
---
--- The XML reconciler calls this when a template renders new records; a
--- model that cannot load or an unknown geometry raises an error naming the node.
function AppKit.sceneGraph(view, records)
	local problems = bridge._sceneGraph(view, records)
	if #problems > 0 then error("SceneView: " .. table.concat(problems, "; "), 2) end
	return true
end

-- SwiftUI animation: Animation values, withAnimation, withTransaction,
-- AnyTransition and the per-view motion modifiers (see ui/animation.lua).
require("ui.animation").install(AppKit, bridge)
-- Local notifications (see ui/notifications.lua).
require("ui.notifications").install(AppKit, bridge)

--- A transparent view reporting clicks and hover positions.
---
--- `onClick(view, x, y, clickCount)` and `onHover(view, x, y)` receive
--- top-left coordinates; hover reports nil coordinates when the pointer
--- leaves. Charts place one over their marks to hit test in Lua.
--- @prop onClick function optional. Click callback.
--- @prop onHover function optional. Hover callback.
--- @prop onDrag function optional. `onDrag(view, x, y) -> path`: dragging from that point drags the file.
--- @prop onKey function optional. `onKey(view, key) -> handled`; the view takes keyboard focus when clicked.
--- @platform AppKit uses the AppKit implementation.
function AppKit.PointerView(props)
	props = props or {}
	if props.width and not props.fixedWidth then props.fixedWidth = props.width end
	if props.height and not props.fixedHeight then props.fixedHeight = props.height end
	local view = bridge._pointerView(props.onClick, props.onHover, props.onDrag, props.onKey)
	local layoutProps = {}
	for key, value in pairs(props) do
		if key ~= "onClick" and key ~= "onHover" and key ~= "onDrag" and key ~= "onKey" then layoutProps[key] = value end
	end
	return applyLayout(view, layoutProps)
end

--- Draws a squarified treemap from `TreemapNode` records.
---
--- Nested nodes (`parent`) are drawn inside their parent below a header band holding their label.
--- Colors are muted semantic colors that lighten with depth; `hatched` marks
--- reclaimable space. Clicking selects a cell and hovering outlines it.
--- @prop onSelect function optional. `onSelect(id, clickCount)`.
--- @prop onHover function optional. `onHover(id)`; nil when leaving.
--- @prop selected string optional. Id of the initially selected cell.
--- @prop onBack function optional. Delete goes up a level (keyboard).
--- @prop dragItem function optional. `dragItem(id) -> path`: dragging a cell drags its file.
--- @prop accessibilityLabel string optional. Summary read by VoiceOver.
--- @example <Treemap height="320"><TreemapNode id="a" value="3" color="systemBlue" label="Apps" /></Treemap>
--- @platform AppKit uses the AppKit implementation.
function AppKit.Treemap(props)
	return require("ui.treemap").view(bridge, applyLayout, props)
end

--- Returns the volume's capacities in bytes: `total`, `available` (free),
--- `important` (free plus purgeable storage macOS will release) and
--- `opportunistic`. Nil when the path is not on a readable volume.
function AppKit.volumeCapacity(path)
	return bridge._volumeCapacity(path)
end

--- Draws a pie or donut chart from `SectorMark` records (SwiftUI Charts).
---
--- Each sector is a native Arc stroke; array views other than marks are
--- centered over the chart, typically a total inside the hole.
--- @prop innerRadius number optional. Hole radius as a fraction of the outer radius (0 draws a pie).
--- @prop angularInset number optional. Gap between neighbouring sectors, in points.
--- @prop scalable boolean optional. Lays the sectors out in `diameter` units and scales them to fill the room the chart is given, centered.
--- @prop diameter number optional. With `scalable`, the chart's geometry in units (default 360).
--- @prop accessibilityLabel string optional. Summary read by VoiceOver.
--- @example <SectorChart width="180" height="180" innerRadius="0.62"><SectorMark value="40" color="systemBlue" /></SectorChart>
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.SectorChart(props)
	return require("ui.sectors").chart(AppKit, props)
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
			table.insert(data, v)
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

--- Seconds of monotonic system time, for measuring real intervals: a
--- `sleep` resumes late whenever the main run loop is busy.
function AppKit.uptime()
	return bridge._uptime()
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

--- A navigation destination: one content view plus its title, toolbar items
--- and presentation, as SwiftUI's `.navigationTitle` and `.toolbar` modifiers.
--- Push the returned controller onto a NavigationStack.
--- @tag Page
--- @prop title string optional. Navigation title.
--- @prop toolbar table optional. ToolbarItem records; `placement` is principal, primaryAction, topBarLeading, topBarTrailing, cancellationAction, confirmationAction or keyboard (one view child, shown above the keyboard while a text input edits; AppKit leaves it out).
--- @prop hidesTabBar boolean optional. Hides the tab bar while the page is visible (UIKit).
--- @prop titleDisplayMode string optional. automatic, inline or large (UIKit).
--- @prop backButtonDisplayMode string optional. default, generic or minimal (UIKit).
--- @prop onDisappear function optional. Called once when the page leaves the stack.
--- @platform AppKit puts toolbar items and a navigational back item in the window toolbar. UIKit uses the navigation bar.
function AppKit.Page(props)
	assert(type(props) == "table" and type(props.content) == "userdata", "Page requires one content view")
	-- Keyboard items ride above an iOS keyboard; a Mac keyboard has no such
	-- bar, and SwiftUI shows them only in the Touch Bar.
	local toolbar = {}
	for _, item in ipairs(props.toolbar or {}) do
		if item.placement ~= "keyboard" then table.insert(toolbar, item) end
	end
	local controller = bridge._hostingController(props.content, props.onDisappear, toolbar)
	controller.title = props.title or ""
	return controller
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
--- @prop path table optional. A `ui.navigation`.Path value path.
--- @prop destinations table optional. Map path types to destination view builders.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function AppKit.NavigationStack(props)
	props = props or {}
	local root = AppKit.HostingController(props.content or props[1])
	root.title = props.title or ""
	local host = applyLayout(bridge._navigationStack(root), props)
	navScreenScopes[host] = {}
	-- The toolbar back item pops like popScreen so screen scopes close.
	bridge._navigationOnBack(host, function() AppKit.popScreen(host) end)
	if props.path then
		for kind, builder in pairs(props.destinations or {}) do
			props.path:registerDestination(kind, builder)
		end
		require("ui.navigation").bindPath(props.path,
			function(value, builder)
				AppKit.pushScreen(host, type(value) == "table" and value.title or nil,
					function() return builder(value) end)
			end,
			function() AppKit.popScreen(host) end)
	end
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

-- Moves a file or folder into `folder` off the main thread, across disks
-- too; `completion(ok, message, destination)` runs on the main thread. An
-- existing item of the same name is never replaced.
function AppKit.moveItem(path, folder, completion)
	bridge._moveItem(path, folder, completion)
end

-- The system Quick Look panel (Finder's Space bar) for `paths`, starting at
-- `index`; an empty list closes it.
function AppKit.quickLook(paths, index)
	bridge._quickLook(paths or {}, index or 1)
end

-- Bundle identifiers of the running apps.
function AppKit.runningApplications()
	return bridge._runningApplications()
end

-- The installed app for a bundle identifier, wherever it lives, or nil.
function AppKit.applicationPath(bundleIdentifier)
	return bridge._applicationPath(bundleIdentifier)
end

-- Starts a new instance of this app and quits once it runs;
-- `onFailure(message)` runs if it could not start.
function AppKit.relaunch(onFailure)
	bridge._relaunch(onFailure)
end

-- `{inode, device, symlink}` for a path (lstat), or nil when it is gone.
function AppKit.fileIdentity(path)
	return bridge._fileIdentity(path)
end

-- `handler(paths)` receives folders and files opened with the app: dropped
-- on its Dock icon or chosen with Open With in the Finder. Opens that
-- arrive before a handler is set are delivered once it is.
function AppKit.onOpenFiles(handler)
	bridge._onOpenFiles(handler)
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

--- Watches files or directory trees for changes (FSEvents).
---
--- `callback(events)` receives batches of `{path, id, created, removed,
--- renamed, modified, directory, rescan, historyDone}`. Options: `since`, an
--- event ID from `AppKit.latestEventId()` to replay what changed after it,
--- and `latency` in seconds. Returns a handle whose `cancel()` stops the
--- watch; the current Scope cancels it when disposed, so a watch lives as
--- long as the window or controller that made it.
--- @platform AppKit FSEvents. UIKit does not support file system watching.
function AppKit.watch(paths, callback, options)
	options = options or {}
	local token = bridge._watch(paths, callback, options.since, options.latency)
	local handle = {}
	function handle.cancel()
		if token then bridge._unwatch(token); token = nil end
	end
	function handle:dispose() handle.cancel() end
	function handle:isDisposed() return token == nil end
	local scope = Scope.current()
	if scope then scope:add(handle) end
	return handle
end

--- A security-scoped bookmark for `path`, as text to store; nil and a
--- message when the item cannot be bookmarked.
function AppKit.bookmark(path)
	return bridge._bookmark(path)
end

--- Resolves a bookmark from `AppKit.bookmark`: the item's current path and
--- whether the bookmark is stale (recreate and store it again), or nil,
--- false and a message. Access to the item lasts until the app quits.
function AppKit.resolveBookmark(text)
	return bridge._resolveBookmark(text)
end

--- Page dots, as UIPageControl draws them; AppKit has no such class.
--- `currentPage` is zero-based and can be set later; `onChange(page)` runs
--- when a dot is clicked.
--- @prop numberOfPages number optional. How many dots.
--- @prop currentPage number optional. Zero-based index of the current page.
--- @prop onChange function optional. Called with the clicked page.
--- @example <PageControl numberOfPages="5" currentPage="0" />
--- @platform AppKit composes SF Symbol dots. UIKit uses UIPageControl.
function AppKit.PageControl(props)
	props = props or {}
	return applyLayout(bridge._pageControl(props.numberOfPages or 0, props.currentPage or 0, props.onChange), props)
end

--- The person's home folder, from the user database. Inside the App
--- Sandbox HOME names the app's container instead.
function AppKit.homeDirectory()
	return bridge._homeDirectory()
end

--- The standard open panel for one folder; returns its path or nil.
--- `options`: `directory` it opens at, `message` above the browser, and
--- `prompt` for the default button.
function AppKit.pickFolder(title, options)
	return bridge._pickFolder(title, options)
end

--- The newest file system event ID; store it and pass it as `since` later.
function AppKit.latestEventId()
	return bridge._latestEventId()
end

--- The app's own folder in Application Support (`name` is one path
--- component), created on first use; nil and a message when unavailable.
--- Resolved by NSFileManager, so a sandboxed app gets its container's folder.
function AppKit.applicationSupportDirectory(name)
	return bridge._applicationSupportDirectory(name)
end

function AppKit.diskSpace(path)
	return bridge._diskSpace(path)
end

return AppKit
