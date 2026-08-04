-- AppKitNative is supplied by the host runtime. Keeping it private lets the
-- public AppKit module remain a single dylib with a stable declarative API.
local bridge = require("AppKitNative")

-- XML-generated native exports are the public module. Lua only adds compound
-- declarative components whose behavior cannot be expressed as a native class
-- declaration.
local AppKit = bridge

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
	"paddingVertical",
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
}

local function applyLayout(view, props)
	if type(props) ~= "table" then return view end
	for _, key in ipairs(layout_properties) do
		if props[key] ~= nil then
			view[key] = props[key]
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

function AppKit.Window(props)
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
		win = bridge._window(title, width, height,
			transparent_titlebar, hide_title, toolbar,
			props.toolbarLabels == true)
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
			props.detail)
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

function AppKit.VStack(props)
	local view = bridge._vstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

function AppKit.HStack(props)
	local view = bridge._hstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

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
function AppKit.Separator(props)
	return applyLayout(bridge._separator(), props)
end

function AppKit.Group(children)
	children = children or {}
	children.__appkitGroup = true
	return children
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

	local v = bridge._textField()
	v.text = text
	v.bezeled = false
	v.drawsBackground = false
	v.editable = false
	v.selectable = false

	if size and size > 0 then
		v.font = bridge._font(size, weight)
	end
	if type(arg) == "table" and arg.color then
		v.textColor = bridge._systemColor(arg.color)
	end
	if type(arg) == "table" and arg.lineLimit then
		v.lineLimit = arg.lineLimit
	end
	if type(arg) == "table" and arg.truncation then
		local modes = { head = 3, tail = 4, middle = 5 }
		v.lineBreakMode = modes[arg.truncation] or 4
	end

	v:sizeToFit()
	return applyLayout(v, type(arg) == "table" and arg or nil)
end

function AppKit.TextField(props)
	if type(props) ~= "table" then
		props = { value = tostring(props or "") }
	end
	local field = bridge._textField()
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
	return applyLayout(field, props)
end

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

function AppKit.Title(arg)
	return AppKit.Text({
		type(arg) == "table" and arg[1] or arg,
		size = 22,
		weight = "bold",
	})
end

function AppKit.Image(arg)
	local path
	local props
	if type(arg) == "table" then
		path = arg[1] or ""
		props = arg
	elseif type(arg) == "string" then
		path = arg
	else
		path = tostring(arg)
	end
	return applyLayout(bridge._image(resolveImage(path)), props)
end

function AppKit.SystemImage(arg)
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

function AppKit.Spacer(props)
	return applyLayout(bridge._spacer(), props)
end

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

	if props.data and type(props.data) == "table" then
		tv:replaceRows(props.data)
	end
	if type(props.onSelect) == "function" then
		tv:onRowSelect(props.onSelect)
	end
	if type(props.onActivate) == "function" then
		tv:onRowActivate(props.onActivate)
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

function AppKit.ToolbarItem(window, identifier)
	local item = bridge._toolbar_item(window, identifier)
	if not item then
		error("toolbar item not found: " .. tostring(identifier))
	end
	return item
end

function AppKit.Button(props)
	local title = type(props) == "table" and (props.title or props[1] or "") or ""
	local action = type(props) == "table" and props.action or nil
	local button
	local compound = type(props) == "table"
		and (props.subtitle or props.systemImage or props.detail
			or props.style == "primary" or props.style == "plain"
			or props.style == "row" or props.style == "link")
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
	return applyLayout(button, props)
end

AppKit.ActionButton = AppKit.Button

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
	return applyLayout(toggle, props)
end

function AppKit.Separator(props)
	local v = bridge._box()
	v.boxType = 2
	v.fixedHeight = 1
	v.flexGrow = 1
	return applyLayout(v, props)
end

function AppKit.Divider(props)
	props = props or {}
	local v = bridge._box()
	v.boxType = 2
	if props.orientation == "vertical" then
		v.fixedWidth = 1
		v.flexGrow = 1
	else
		v.fixedHeight = 1
		v.flexGrow = 1
	end
	return applyLayout(v, props)
end

function AppKit.ProgressView(props)
	local v = bridge._progressIndicator()
	v.style = 1
	v.displayedWhenStopped = false
	return applyLayout(v, props)
end

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
		return AppKit.PathView(props)
	end
	local minY, maxY = data[1], data[1]
	for _, v in ipairs(data) do
		if v < minY then minY = v end
		if v > maxY then maxY = v end
	end
	local range = maxY - minY
	if range == 0 then range = 1 end
	local v = AppKit.PathView(props)
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

return AppKit
