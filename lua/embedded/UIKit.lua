-- UIKitNative is registered by the host before this layer runs.
local bridge = require("UIKitNative")
local UIKit = bridge
local Scope = require("ui.scope")(bridge)
UIKit.Scope = Scope
UIKit.SidebarMetrics = {
	iconSize = bridge.sidebarIconSize,
	iconSlotWidth = bridge.sidebarIconSlotWidth,
	rowPadding = bridge.sidebarRowPadding,
	expandedPadding = bridge.sidebarExpandedPadding,
	collapsedPadding = bridge.sidebarCollapsedPadding,
	expandedWidth = bridge.sidebarExpandedWidth,
	compactWidth = bridge.sidebarCompactWidth,
	collapsedWidth = bridge.sidebarCollapsedWidth,
}

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
	"cornerRadius",
	"clipsToBounds",
	"ignoresSafeArea",
	"contentModeName",
	"background",
}

local function applyLayout(view, props)
	if type(props) ~= "table" then return view end
	for _, key in ipairs(layout_properties) do
		if props[key] ~= nil then
			if key == "background" then
				view.backgroundColor = bridge._systemColor(props[key])
			else
				view[key] = props[key]
			end
		end
	end
	return view
end

local function addChildren(parent, children)
	if type(children) ~= "table" then return end
	for _, child in ipairs(children) do
		if type(child) == "userdata" then
			parent:add(child)
		elseif type(child) == "table" and child.__appkitGroup then
			addChildren(parent, child)
		end
	end
end

local function asViewController(content)
	if content == nil then
		error("UIKit.Window requires content")
	end
	if type(content) == "table" then
		local stack = UIKit.VStack(content)
		return bridge._hostingController(stack)
	end
	local ok, vc = pcall(function()
		return bridge._hostingController(content)
	end)
	if ok then return vc end
	return content
end

--- Creates the app window and hosts the rendered root view.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop appearance string optional. Window appearance: `system`, `light`, or `dark`.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @example <Window title="Example" />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Window(props)
	props = props or {}
	local scope = Scope.push()
	local content = props.content or props[1]
	local vc = asViewController(content)
	local userInterfaceStyles = { automatic = 0, light = 1, dark = 2 }
	if props.appearance and userInterfaceStyles[props.appearance] ~= nil then
		vc.overrideUserInterfaceStyle = userInterfaceStyles[props.appearance]
	end
	-- If scene installation fails, do not leak the pushed scope.
	local ok, win = pcall(bridge._installScene, vc, props.title or "")
	if not ok then
		scope:close()
		error(win, 2)
	end
	-- Like AppKit, window teardown closes the scope automatically so apps
	-- never call dispose by hand.
	if bridge._onWindowClose then
		bridge._onWindowClose(win, function()
			scope:close()
		end)
	end
	return win
end

--- Presents mutually exclusive content in native tabs.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop selected table optional. Selected option, tab, or row identifier.
--- @prop tabs table optional. Tab definitions containing a title and content.
--- @example <TabView />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.TabView(props)
	props = props or {}
	local tbc = bridge._tabview(props.minimizeBehavior or "automatic")
	local tabs = props.tabs or {}
	for _, tab in ipairs(tabs) do
		if type(tab) == "table" and tab.__tab then
			local vc = asViewController(tab.content)
			bridge._tabViewAddTab(tbc, vc, tab.title or "", tab.systemImage or "")
		end
	end
	if props.selected ~= nil then
		bridge._tabViewSelectTab(tbc, props.selected)
	end
	if type(props.onChange) == "function" then
		bridge._tabViewOnChange(tbc, props.onChange)
	end
	return tbc
end

--- Creates a fixed-size preview root for the IDE canvas.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <Preview />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Preview(props)
	return applyLayout(bridge._preview(), props or {})
end

function UIKit.HostingController(view)
	return bridge._hostingController(view)
end

local navScreenScopes = setmetatable({}, { __mode = "k" })
local sheetScopes = {}

--- Manages a stack of screens and navigation transitions.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop path table optional. A `ui.navigation`.Path value path.
--- @prop destinations table optional. Map path types to destination view builders.
--- @prop hidesNavigationBar boolean optional. Hides the navigation bar when true.
--- @prop hidesTabBar boolean optional. Hides the tab bar when true.
--- @prop largeTitle boolean optional. Uses the large navigation title style when true.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.NavigationStack(props)
	props = props or {}
	local content = props.content or props[1]
	local root = asViewController(content)
	local navigation = bridge._navigationStack(root, props.hidesNavigationBar == true)
	if props.title then root.title = props.title end
	if props.largeTitle ~= nil then
		navigation.navigationBar.prefersLargeTitles = props.largeTitle
	end
	if props.hidesTabBar ~= nil then
		root.hidesBottomBarWhenPushed = props.hidesTabBar
	end
	navScreenScopes[navigation] = {}
	if props.path then
		for kind, builder in pairs(props.destinations or {}) do
			props.path:registerDestination(kind, builder)
		end
		require("ui.navigation").bindPath(props.path,
			function(value, builder)
				UIKit.pushScreen(navigation, type(value) == "table" and value.title or nil,
					function() return builder(value) end)
			end,
			function() UIKit.popScreen(navigation) end)
	end
	return navigation
end

function UIKit.pushScreen(nav, title, builder)
	assert(nav ~= nil, "pushScreen requires a navigation stack")
	assert(type(builder) == "function", "pushScreen requires a builder function")
	local stack = navScreenScopes[nav]
	assert(stack ~= nil, "pushScreen requires a NavigationStack host")
	local screenScope = Scope.push()
	local ok, content = pcall(builder)
	if not ok then
		screenScope:close()
		error(content, 2)
	end
	local vc = asViewController(content)
	if title then vc.title = title end
	nav:push(vc)
	table.insert(stack, screenScope)
	return vc
end

function UIKit.popScreen(nav)
	assert(nav ~= nil, "popScreen requires a navigation stack")
	local stack = navScreenScopes[nav]
	assert(stack ~= nil, "popScreen requires a NavigationStack host")
	nav:pop()
	local screenScope = table.remove(stack)
	if screenScope then screenScope:close() end
end

--- Navigates to a destination within a navigation stack.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop destination string optional. Navigation destination associated with the link.
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop navigation string optional. Navigation stack that receives the destination.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @platform UIKit uses the UIKit implementation.
function UIKit.NavigationLink(props)
	props = props or {}
	assert(props.navigation, "NavigationLink requires a navigation stack")
	assert(props.destination, "NavigationLink requires a destination")
	local destination = asViewController(props.destination)
	return applyLayout(bridge._navigationLink(props.navigation, destination,
		props.title or props.label or props[1] or "Open"), props)
end

function UIKit.presentSheet(contentOrBuilder, props)
	local content = contentOrBuilder
	if type(contentOrBuilder) == "function" then
		local sheetScope = Scope.push()
		local ok, built = pcall(contentOrBuilder)
		if not ok then
			sheetScope:close()
			error(built, 2)
		end
		content = built
		local sheet = bridge._presentSheet(asViewController(content), props or {})
		table.insert(sheetScopes, sheetScope)
		return sheet
	end
	local sheetScope = Scope.push()
	local sheet = bridge._presentSheet(asViewController(content), props or {})
	table.insert(sheetScopes, sheetScope)
	return sheet
end

function UIKit.dismiss()
	local sheetScope = table.remove(sheetScopes)
	local ok, err = pcall(bridge._dismiss)
	if sheetScope then sheetScope:close() end
	if not ok then error(err, 2) end
end

function UIKit.confirm(props)
	props = props or {}
	return bridge._confirm(props.title or "Confirm", props.message or "",
		props.destructive or "OK", props.cancel or "Cancel", props.action)
end

--- Arranges child views vertically with sibling spacing.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <VStack />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.VStack(props)
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
function UIKit.HStack(props)
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
function UIKit.FlowStack(props)
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
		content[#content + 1] = UIKit.Text({ header, weight = "bold" })
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
function UIKit.Section(props)
	props = props or {}
	return UIKit.VStack(stackChildren(props, props.header))
end

--- Groups related controls inside a titled native box.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop background color optional. Background color or semantic background value.
--- @prop cornerRadius number optional. Corner radius for this component where supported.
--- @prop header table optional. Section or group heading.
--- @prop padding number optional. Component-specific setting passed to the native control.
--- @example <GroupBox />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.GroupBox(props)
	props = props or {}
	local content = stackChildren(props, props.header)
	content.padding = props.padding or 12
	content.background = props.background or "background"
	content.cornerRadius = props.cornerRadius or 10
	content.clipsToBounds = true
	return UIKit.VStack(content)
end

--- Arranges controls as a settings or data-entry form.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <Form />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Form(props)
	props = props or {}
	local content = {
		spacing = props.spacing or 12,
		alignment = props.alignment or "leading",
	}
	for _, child in ipairs(props) do content[#content + 1] = child end
	return applyLayout(UIKit.VStack(content), props)
end

--- Pairs a descriptive label with its value or child controls.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop labelWeight value optional. System font weight for the label.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <LabeledContent />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.LabeledContent(props)
	props = props or {}
	local row = { spacing = props.spacing or 12, alignment = "center" }
	if props.label and props.label ~= "" then
		row[#row + 1] = UIKit.Text({ props.label, weight = props.labelWeight })
	end
	for _, child in ipairs(props) do row[#row + 1] = child end
	return applyLayout(UIKit.HStack(row), props)
end

--- Groups related controls into a compact row.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @example <ControlGroup />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.ControlGroup(props)
	props = props or {}
	local row = { spacing = props.spacing or 8, alignment = props.alignment or "center" }
	for _, child in ipairs(props) do row[#row + 1] = child end
	return applyLayout(UIKit.HStack(row), props)
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
function UIKit.DisclosureGroup(props)
	props = props or {}
	local content = UIKit.VStack({
		spacing = props.spacing or 8,
		alignment = props.alignment or "leading",
	})
	for _, child in ipairs(props) do content:add(child) end
	local container = UIKit.VStack { spacing = 8, alignment = "leading" }
	local expanded = props.expanded ~= false
	local button = UIKit.Button {
		title = props.label or props.header or "Details",
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
function UIKit.OutlineGroup(props)
	props = props or {}
	local data = props.data or props.items or {}
	assert(type(data) == "table", "OutlineGroup requires data or items")
	local content = outlineItems(UIKit, data, props.expanded)
	content.spacing = props.spacing or 4
	content.alignment = props.alignment or "leading"
	return applyLayout(UIKit.VStack(content), props)
end

--- Layers child views in the same coordinate area.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <ZStack />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.ZStack(props)
	local view = bridge._zstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
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
function UIKit.ScrollView(props)
	assert(type(props) == "table", "ScrollView requires a property table")
	local content = props.content or props[1]
	assert(type(content) == "userdata", "ScrollView requires one content view")
	return applyLayout(bridge._scrollView(content, props.contentWidth or 0,
		props.contentHeight or 0, props.horizontal == true, props.vertical ~= false), props)
end

--- Edits a single line of text.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop accessibilityLabel value optional. Component-specific setting passed to the native control.
--- @prop bezeled boolean optional. Shows the native bezel when true.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop editable boolean optional. Allows text editing when true.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop onCommand function optional. Callback invoked for the corresponding keyboard command.
--- @prop placeholder string optional. Component-specific setting passed to the native control.
--- @prop secure boolean optional. Masks entered text when true.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @prop weight value optional. Component-specific setting passed to the native control.
--- @example <TextField />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.TextField(props)
	if type(props) ~= "table" then props = { value = tostring(props or "") } end
	local field = bridge._textField(props.value or props[1] or "")
	field.placeholder = props.placeholder or ""
	field.borderStyle = props.bezeled == false and 0 or 3
	field.secureTextEntry = props.secure == true
	field.enabled = props.disabled ~= true and props.editable ~= false
	if props.size then field.font = bridge._font(props.size, props.weight) end
	if props.accessibilityLabel then field.accessibilityLabel = props.accessibilityLabel end
	bridge._textFieldCallbacks(field, props.onChange, props.onCommand)
	field:sizeToFit()
	return applyLayout(field, props)
end

--- Edits multiline text.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop drawsBackground boolean optional. Draws the control’s background when true.
--- @prop editable boolean optional. Allows text editing when true.
--- @prop italic boolean optional. Component-specific setting passed to the native control.
--- @prop selectable boolean optional. Allows text or rows to be selected when true.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop text string optional. Initial or displayed text value.
--- @prop value table optional. Current selected, edited, or measured value.
--- @prop weight value optional. Component-specific setting passed to the native control.
--- @prop wrapMode string optional. Text wrapping mode.
--- @example <TextEditor />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.TextEditor(props)
	props = props or {}
	local v = bridge._textEditor(props.text or props.value or "",
		props.editable, props.selectable, props.drawsBackground)
	if props.size and props.size > 0 then
		v.font = bridge._font(props.size, props.weight, props.italic)
	end
	if props.wrapMode == false then
		v.textContainer.lineBreakMode = 1
	end
	return applyLayout(v, props)
end

--- Provides native search input and search-specific behavior.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop accessibilityLabel value optional. Component-specific setting passed to the native control.
--- @prop placeholder string optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <SearchField />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.SearchField(props)
	props = props or {}
	local v = bridge._searchField(props.value or props[1] or "",
		props.placeholder or "Search")
	if props.accessibilityLabel then
		v.accessibilityLabel = props.accessibilityLabel
	end
	return applyLayout(v, props)
end

--- Combines an icon and title in a standard platform label.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop accessibilityLabel value optional. Component-specific setting passed to the native control.
--- @prop alignment value optional. Component-specific setting passed to the native control.
--- @prop color color optional. Component-specific setting passed to the native control.
--- @prop iconSize number optional. Component-specific setting passed to the native control.
--- @prop iconWeight value optional. System symbol weight for the label icon.
--- @prop italic boolean optional. Component-specific setting passed to the native control.
--- @prop lineLimit number optional. Maximum number of visible text lines.
--- @prop lines number optional. Maximum number of visible text lines.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop spacing number optional. Component-specific setting passed to the native control.
--- @prop systemImage string optional. Component-specific setting passed to the native control.
--- @prop truncation string optional. Text truncation position: `head`, `middle`, or `tail`.
--- @prop weight value optional. Component-specific setting passed to the native control.
--- @prop wrapping boolean optional. Component-specific setting passed to the native control.
--- @platform UIKit uses the UIKit implementation.
function UIKit.Label(arg)
	local text
	local props
	if type(arg) == "table" then
		text = arg[1] or arg.text or arg.value or ""
		props = arg
	elseif type(arg) == "string" then
		text = arg
	else
		text = tostring(arg)
	end
	if type(props) == "table" and props.systemImage then
		local row = {
			spacing = props.spacing or 6,
			alignment = "center",
			UIKit.SystemImage({
				name = props.systemImage,
				accessibilityLabel = props.accessibilityLabel,
				size = props.iconSize or props.size,
				weight = props.iconWeight or props.weight,
				color = props.color,
			}),
			UIKit.Label({ text, size = props.size, weight = props.weight,
				italic = props.italic, color = props.color,
				lineLimit = props.lineLimit, truncation = props.truncation, wrapping = props.wrapping }),
		}
		return applyLayout(UIKit.HStack(row), props)
	end
	local v = bridge._label(text)
	if type(props) == "table" then
		if props.size and props.size > 0 then
			v.font = bridge._font(props.size, props.weight, props.italic)
		end
		local lines = props.lineLimit or props.lines
		if lines then
			v.numberOfLines = lines
			if lines > 1 then v.lineBreakMode = 0 end
		end
		if props.wrapping then v.lineBreakMode = props.wrapping == "character" and 1 or 0 end
		if props.truncation then
			local modes = { head = 3, tail = 4, middle = 5 }
			v.lineBreakMode = modes[props.truncation] or 4
		end
		if props.color then
			v.textColor = bridge._systemColor(props.color)
		end
		if props.alignment then
			v.textAlignment = ({ leading = 0, center = 1, trailing = 2 })[props.alignment] or 0
		end
		v:sizeToFit()
	end
	return applyLayout(v, props)
end

UIKit.Text = UIKit.Label

--- Displays prominent window or section title text.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Title(arg)
	return UIKit.Label({
		type(arg) == "table" and (arg[1] or arg.text) or arg,
		size = 22,
		weight = "bold",
	})
end

--- Displays a raster or vector image asset.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop contentMode string optional. Image scaling mode such as fit or fill.
--- @example <Image />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Image(arg)
	local path
	local props
	if type(arg) == "table" then
		path = arg[1] or arg.src or arg.path or ""
		props = arg
	elseif type(arg) == "string" then
		path = arg
	else
		path = tostring(arg)
	end
	if bridge._readFile then
		local body, err = bridge._readFile(path)
		if err then error(err) end
		local view = bridge._imageData(body)
		if props and props.contentMode then view.contentModeName = props.contentMode end
		return applyLayout(view, props)
	end
	local view = bridge._image(path)
	if props and props.contentMode then view.contentModeName = props.contentMode end
	return applyLayout(view, props)
end

--- Displays an SF Symbol using the platform image system.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <SystemImage />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.SystemImage(arg)
	if type(arg) ~= "table" then
		arg = { tostring(arg) }
	end
	local name = arg.name or arg[1] or ""
	local description = arg.accessibilityLabel or arg.label or name
	local size = arg.size or 17
	local weight = arg.weight or "regular"
	local color = arg.color or "accent"
	return applyLayout(
		bridge._systemImage(name, description, size, weight, color),
		arg)
end

--- Consumes flexible space between neighboring views.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @example <Spacer />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Spacer(props)
	return applyLayout(bridge._spacer(), props)
end

--- Indicates pages and allows selecting the current page.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop currentPage number optional. Zero-based index of the currently visible page.
--- @prop numberOfPages number optional. Component-specific setting passed to the native control.
--- @prop pages table optional. Page data used to construct the page control.
--- @platform UIKit uses the UIKit implementation.
function UIKit.PageControl(props)
	props = props or {}
	return applyLayout(bridge._pageControl(props.numberOfPages or props.pages or 0,
		props.currentPage or 0), props)
end

--- Fills content with a linear color gradient.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop bottomAlpha number optional. Opacity of the gradient at the bottom edge.
--- @prop middleAlpha number optional. Component-specific setting passed to the native control.
--- @prop middleLocation number optional. Position of the middle gradient stop, from 0 to 1.
--- @prop topAlpha number optional. Opacity of the gradient at the top edge.
--- @platform UIKit uses the UIKit implementation.
function UIKit.LinearGradient(props)
	props = props or {}
	return applyLayout(bridge._linearGradient(props.topAlpha or 0,
		props.middleAlpha or 0.5, props.middleLocation or 0.6,
		props.bottomAlpha or 0.82), props)
end

--- Displays rows of data in a native table or list control.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop bordered boolean optional. Shows the native border when true.
--- @prop columns table optional. Column descriptors defining the table structure.
--- @prop data table optional. Input rows or values consumed by the component.
--- @prop header table optional. Section or group heading.
--- @prop height number optional. Component-specific setting passed to the native control.
--- @prop width number optional. Component-specific setting passed to the native control.
--- @example <List />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.List(props)
	local columns = props.columns
	if not columns or type(columns) ~= "table" then
		error("List requires a 'columns' property (array of {id, title})")
	end
	local width = props.width or 400
	local height = props.height or 200
	local tv = bridge._tableview(columns, width, height, {
		header = props.header ~= false,
		bordered = props.bordered == true,
	})
	if props.data and type(props.data) == "table" then
		for _, row in ipairs(props.data) do
			if type(row) == "table" then
				tv:addRow(row)
			end
		end
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
	return applyLayout(tv, props)
end

--- Runs an action when the user activates a native button.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop accessibilityLabel value optional. Component-specific setting passed to the native control.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop role string optional. Semantic action role, such as destructive.
--- @prop size number optional. Component-specific setting passed to the native control.
--- @prop style string optional. Component-specific setting passed to the native control.
--- @prop systemImage string optional. Component-specific setting passed to the native control.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @prop truncation string optional. Text truncation position: `head`, `middle`, or `tail`.
--- @prop weight value optional. Component-specific setting passed to the native control.
--- @example <Button title="Example" />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Button(props)
	local title = type(props) == "table" and (props.title or props[1] or "") or ""
	local action = type(props) == "table" and props.action or nil
	local button
	local font = type(props) == "table" and props.size and bridge._font(props.size, props.weight) or nil
	local style = type(props) == "table" and props.style or nil
	if action then
		button = bridge._button(title, action, style or "default",
			props.systemImage or "", props.role or "", font)
	else
		button = bridge._button(title, nil, style or "default",
			props.systemImage or "", props.role or "", font)
	end
	if type(props) == "table" and props.truncation then
		local modes = { head = 3, tail = 4, middle = 5 }
		button.titleLabel.lineBreakMode = modes[props.truncation] or 4
		button.titleLabel.numberOfLines = 1
	end
	if type(props) == "table" and props.disabled ~= nil then
		button.enabled = not props.disabled
	end
	if type(props) == "table" and props.accessibilityLabel then
		button.accessibilityLabel = props.accessibilityLabel
	end
	return applyLayout(button, props)
end

--- Displays a native WKWebView and optionally binds it to a WebPage.
--- @tag WebView
--- @prop page table optional. Observable `ui.webpage` state object.
--- @prop url string optional. Initial URL when no page object is supplied.
--- @example <WebView page="page" />
--- @platform UIKit WKWebView.
function UIKit.WebView(props)
	props = props or {}
	local page = props.page
	local url = props.url or (page and page.url) or "about:blank"
	local weakPage = setmetatable({ page }, { __mode = "v" })
	local view = bridge._webView(url, function(event, value)
		local target = weakPage[1]
		if target then target:_nativeEvent(event, value) end
	end)
	view.allowsBackForwardNavigationGestures = props.allowsBackForwardNavigation ~= false
	if props.contentBackground == "hidden" then
		view.backgroundColor = bridge._systemColor("clear")
		view.scrollView.backgroundColor = bridge._systemColor("clear")
		view.opaque = false
	end
	if page then page:_attachNative(view, bridge._webViewAction) end
	return applyLayout(view, props)
end

--- Embeds a view in the current system glass effect.
--- @tag GlassEffect
--- @prop content value required. The view rendered inside the glass effect.
--- @prop style string optional. `regular` or `clear`.
--- @prop cornerRadius number optional. Clips the effect to the requested shape.
--- @example <GlassEffect style="regular"><VStack>...</VStack></GlassEffect>
--- @platform UIKit UIGlassEffect and UIVisualEffectView (iOS 26+).
function UIKit.GlassEffect(props)
	props = props or {}
	local content = props.content or props[1]
	assert(content, "GlassEffect requires content")
	return applyLayout(bridge._glassEffect(content, props.style or "regular",
		props.cornerRadius or 0), props)
end

--- Opens or navigates to a destination when activated.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop label value optional. Component-specific setting passed to the native control.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @prop url string optional. Component-specific setting passed to the native control.
--- @example <Link />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Link(props)
	props = props or {}
	assert(props.url, "Link requires a URL")
	return applyLayout(bridge._link(props.title or props.label or props[1] or props.url,
		props.url), props)
end

--- Presents a native menu of related commands.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop children table optional. Component-specific setting passed to the native control.
--- @prop items table optional. Component-specific setting passed to the native control.
--- @prop title value optional. Component-specific setting passed to the native control.
--- @example <Menu />
--- @platform UIKit uses the UIKit implementation.
function UIKit.Menu(props)
	props = props or {}
	return applyLayout(bridge._menu(props.items or props.children or {},
		props.title or "Menu"), props)
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
function UIKit.ContentUnavailable(props)
	props = props or {}
	local content = { spacing = props.spacing or 8, alignment = "center" }
	if props.systemImage then
		content[#content + 1] = UIKit.SystemImage {
			props.systemImage,
			size = props.imageSize or 28,
			color = "secondary",
			accessibilityLabel = props.title or "",
		}
	end
	if props.title then content[#content + 1] = UIKit.Title(props.title) end
	if props.description then
		content[#content + 1] = UIKit.Label {
			props.description,
			alignment = "center",
			color = "secondary",
			lines = props.lines or 0,
		}
	end
	return applyLayout(UIKit.VStack(content), props)
end

--- Displays content using a native visual material.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop content value optional. Rendered child content or the control’s text value.
--- @prop material string optional. Component-specific setting passed to the native control.
--- @platform UIKit uses the UIKit implementation.
function UIKit.MaterialView(props)
	props = props or {}
	local content = props.content or props[1]
	assert(type(content) == "userdata", "MaterialView requires one content view")
	return applyLayout(bridge._materialView(props.material or "regular", content), props)
end

--- Represents an on/off value with a native switch or checkbox.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop is_on value optional. Current on/off value (legacy spelling).
--- @prop label value optional. Component-specific setting passed to the native control.
--- @example <Toggle />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Toggle(props)
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
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop max number optional. Component-specific setting passed to the native control.
--- @prop min number optional. Component-specific setting passed to the native control.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <Slider />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Slider(props)
	props = props or {}
	local slider = bridge._slider(props.min or 0, props.max or 1,
		props.value or props.min or 0, props.onChange)
	if props.disabled ~= nil then slider.enabled = not props.disabled end
	return applyLayout(slider, props)
end

--- Increments or decrements a numeric value.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop max number optional. Component-specific setting passed to the native control.
--- @prop min number optional. Component-specific setting passed to the native control.
--- @prop onChange function optional. Callback invoked when the value changes.
--- @prop step number optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <Stepper />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Stepper(props)
	props = props or {}
	local stepper = bridge._stepper(props.min or 0, props.max or 100,
		props.value or props.min or 0, props.step or 1, props.onChange)
	if props.disabled ~= nil then stepper.enabled = not props.disabled end
	return applyLayout(stepper, props)
end

--- Selects one value from a set of options.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop action function optional. Component-specific setting passed to the native control.
--- @prop disabled boolean optional. Component-specific setting passed to the native control.
--- @prop options table optional. Selectable options or menu entries.
--- @prop style string optional. Component-specific setting passed to the native control.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <Picker />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Picker(props)
	props = props or {}
	local picker = bridge._picker(props.options or {}, props.value or 0, props.action,
		props.style or "automatic")
	if props.disabled ~= nil then picker.userInteractionEnabled = not props.disabled end
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
function UIKit.DatePicker(props)
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
function UIKit.ColorPicker(props)
	props = props or {}
	local picker = bridge._colorPicker(props.color, props.onChange)
	if props.disabled ~= nil then picker.enabled = not props.disabled end
	return applyLayout(picker, props)
end

--- Draws a native separator between adjacent content.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop orientation string optional. Component-specific setting passed to the native control.
--- @example <Separator />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.Separator(props)
	props = props or {}
	return applyLayout(bridge._separator(props.orientation or "horizontal"), props)
end

UIKit.Divider = UIKit.Separator

--- Shows determinate or indeterminate progress.
---
--- This component is backed by the platform control or container. Prefer its XML tag in an `.etlua` template; keep view-tree construction out of controllers.
--- @prop value table optional. Current selected, edited, or measured value.
--- @example <ProgressView />
--- @platform AppKit uses the AppKit implementation. UIKit uses the UIKit implementation.
function UIKit.ProgressView(props)
	props = props or {}
	if props.value ~= nil then
		return applyLayout(bridge._progressView(props.value), props)
	end
	return applyLayout(bridge._progressIndicator(), props)
end

function UIKit.Group(children)
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
function UIKit.Grid(props)
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
		rows[#rows + 1] = UIKit.HStack(rowProps)
	end
	props.content = nil
	for i = #props, 1, -1 do props[i] = nil end
	for _, row in ipairs(rows) do props[#props + 1] = row end
	return UIKit.VStack(props)
end

function UIKit.ForEach(data, content)
	local out = { __appkitGroup = true }
	if type(data) ~= "table" then return out end
	for i, item in ipairs(data) do
		out[#out + 1] = content(item, i)
	end
	return out
end

function UIKit.sleep(seconds)
	local co = coroutine.running()
	if not co then
		error("sleep() must be called from within a coroutine (use async())")
	end
	bridge._timerAfter(seconds, function()
		resumeCoroutine(co)
	end)
	coroutine.yield()
end

function UIKit.async(fn)
	local co = coroutine.create(fn)
	resumeCoroutine(co)
end

function UIKit.fetch(url)
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

function UIKit.json_parse(str)
	local obj, err = bridge._jsonParse(str)
	if err then error(err) end
	return obj
end

function UIKit.fetch_json(url)
	local body = UIKit.fetch(url)
	return UIKit.json_parse(body)
end

return UIKit
