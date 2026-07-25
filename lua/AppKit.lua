local bridge = require("bridge")

local AppKit = {}

local layout_properties = {
	"padding",
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

	local content = bridge._vstack()
	bridge._add(win, content)

	for _, v in ipairs(props) do
		if type(v) == "userdata" then
			bridge._add(content, v)
		end
	end

	bridge._layout(content, width)

	if props.visible ~= false and not _G.__headless then
		bridge._show(win)
	end
	return win
end

function AppKit.VStack(props)
	local view = bridge._vstack()
	if type(props) == "table" then
		applyLayout(view, props)
		for _, v in ipairs(props) do
			if type(v) == "userdata" then
				bridge._add(view, v)
			end
		end
	end
	return view
end

function AppKit.HStack(props)
	local view = bridge._hstack()
	if type(props) == "table" then
		applyLayout(view, props)
		for _, v in ipairs(props) do
			if type(v) == "userdata" then
				bridge._add(view, v)
			end
		end
	end
	return view
end

function AppKit.HSplit(props)
	local view = bridge._hsplit()
	if type(props) == "table" then
		applyLayout(view, props)
		for _, v in ipairs(props) do
			if type(v) == "userdata" then
				bridge._add(view, v)
			end
		end
	end
	return view
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
			coroutine.resume(co)
		end)
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
	if action then
		button = bridge._button(title, action)
	else
		button = bridge._button(title)
	end
	return applyLayout(button, props)
end

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
		coroutine.resume(co)
	end)
	coroutine.yield()
end

function AppKit.async(fn)
	local co = coroutine.create(fn)
	coroutine.resume(co)
end

function AppKit.fetch(url)
	local co = coroutine.running()
	if not co then
		error("fetch() must be called from within a coroutine (use async())")
	end
	local body, err = nil, nil
	bridge._httpGet(url, function(b, e)
		body, err = b, e
		coroutine.resume(co)
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
