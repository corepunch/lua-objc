-- AppKitNative is supplied by the host runtime. Keeping it private lets the
-- public AppKit module remain a single dylib with a stable declarative API.
local bridge = require("AppKitNative")

local AppKit = {}

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
			bridge._add(parent, child)
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
	local width = props.width or 480
	local height = props.height or 360
	local transparent_titlebar = props.transparentTitlebar or false
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
	bridge._setContentSize(win, width, height)
	if props.minWidth or props.minHeight then
		bridge._setWindowMinSize(
			win,
			props.minWidth or width,
			props.minHeight or height)
	end
	local appearance = props.appearance
		or os.getenv("LUA_OBJC_APPEARANCE")
		or _G._LAUNCH_APPEARANCE
	if appearance == "light" or appearance == "dark" or appearance == "system" then
		bridge._setAppearance(win, appearance)
	end

	local content = bridge._vstack()
	bridge._add(win, content)

	addChildren(content, props)

	bridge._layout(content, width)

	if props.visible ~= false and not _G.__headless then
		bridge._show(win)
	end
	return win
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
			bridge._add(root, child)
		end
	else
		-- allow inline children: ns.Preview { ns.Text "hi" }
		addChildren(root, props)
	end
	bridge._layout(root, width)
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

	local v = bridge._create("NSTextField")
	v.stringValue = text
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
		v.maximumNumberOfLines = arg.lineLimit
	end
	if type(arg) == "table" and arg.truncation then
		local modes = { head = 3, tail = 4, middle = 5 }
		v.lineBreakMode = modes[arg.truncation] or 4
	end

	bridge._perform(v, "sizeToFit")
	return applyLayout(v, type(arg) == "table" and arg or nil)
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
		gridLines = props.gridLines,
		style = props.style,
	})

	if props.data and type(props.data) == "table" then
		for _, row in ipairs(props.data) do
			if type(row) == "table" then
				tv:addRow(row)
			end
		end
	end

	if props.refresh and type(props.refresh) == "function" then
		local refresh_fn = props.refresh
		bridge._tableSetRefresh(tv, function(list, on_done)
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
		gridLines = props.gridLines,
		style = props.style,
	})

	if props.data and type(props.data) == "table" then
		for _, item in ipairs(props.data) do
			if type(item) == "table" then
				tv:addRow(item)
			end
		end
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
	local v = bridge._create("NSBox")
	v.boxType = 2
	v.fixedHeight = 1
	v.flexGrow = 1
	return applyLayout(v, props)
end

function AppKit.Divider(props)
	props = props or {}
	local v = bridge._create("NSBox")
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
	local v = bridge._create("NSProgressIndicator")
	v.style = 1
	v.displayedWhenStopped = false
	return applyLayout(v, props)
end

function AppKit.Layout(view, props)
	if type(view) ~= "userdata" then
		error("Layout requires a view userdata")
	end
	return applyLayout(view, props)
end

function AppKit.ProgressStart(progress)
	bridge._perform(progress, "startAnimation:", nil)
end

function AppKit.ProgressStop(progress)
	bridge._perform(progress, "stopAnimation:", nil)
end

function AppKit.ToolbarProgress(window, identifier)
	local item = AppKit.ToolbarItem(window, identifier)
	local restore_view = item.view
	local progress = AppKit.ProgressView()
	bridge._setContentSize(progress, 32, 32)

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
