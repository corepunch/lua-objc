local bridge = require("bridge")

local UI = {}

local layout_properties = {
	"padding",
	"alignment",
	"fixed_width",
	"fixed_height",
	"min_width",
	"min_height",
	"max_width",
	"max_height",
	"flex_grow",
	"flex_shrink",
	"flex_basis",
}

local function apply_layout(view, props)
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

local function resolve_image(name)
	-- check absolute path first
	if name:sub(1, 1) == "/" or name:sub(1, 1) == "~" then
		return name
	end
	-- check relative to cwd
	local f = io.open(name)
	if f then
		f:close()
		return name
	end
	return name
end

function UI.Window(props)
	local title = props.title or "Window"
	local width = props.width or 480
	local height = props.height or 360
	local transparent_titlebar = props.transparent_titlebar or false
	local hide_title = props.hide_title
	if hide_title == nil then hide_title = transparent_titlebar end

	local toolbar = props.toolbar
	local win
	if toolbar then
		win = bridge._window(title, width, height,
			transparent_titlebar, hide_title, toolbar,
			props.toolbar_labels == true)
	else
		win = bridge._window(title, width, height,
			transparent_titlebar, hide_title)
	end
	bridge._set_content_size(win, width, height)

	local content = bridge._vstack()
	bridge._add(win, content)

	for _, v in ipairs(props) do
		if type(v) == "userdata" then
			bridge._add(content, v)
		end
	end

	bridge._layout(content, width)

	bridge._show(win)
	return win
end

function UI.VStack(props)
	local view = bridge._vstack()
	if type(props) == "table" then
		apply_layout(view, props)
		for _, v in ipairs(props) do
			if type(v) == "userdata" then
				bridge._add(view, v)
			end
		end
	end
	return view
end

function UI.HStack(props)
	local view = bridge._hstack()
	if type(props) == "table" then
		apply_layout(view, props)
		for _, v in ipairs(props) do
			if type(v) == "userdata" then
				bridge._add(view, v)
			end
		end
	end
	return view
end

function UI.HSplit(props)
	local view = bridge._hsplit()
	if type(props) == "table" then
		apply_layout(view, props)
		for _, v in ipairs(props) do
			if type(v) == "userdata" then
				bridge._add(view, v)
			end
		end
	end
	return view
end

function UI.Text(arg)
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
	return apply_layout(v, type(arg) == "table" and arg or nil)
end

function UI.Title(arg)
	return UI.Text({
		type(arg) == "table" and arg[1] or arg,
		size = 22,
		weight = "bold",
	})
end

function UI.Image(arg)
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
	return apply_layout(bridge._image(resolve_image(path)), props)
end

function UI.Spacer(props)
	return apply_layout(bridge._spacer(), props)
end

function UI.List(props)
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
				tv:add_row(row)
			end
		end
	end

	return apply_layout(tv, props)
end

function UI.ToolbarItem(window, identifier)
	local item = bridge._toolbar_item(window, identifier)
	if not item then
		error("toolbar item not found: " .. tostring(identifier))
	end
	return item
end

function UI.Button(props)
	local title = type(props) == "table" and (props.title or props[1] or "") or ""
	local action = type(props) == "table" and props.action or nil
	local button
	if action then
		button = bridge._button(title, action)
	else
		button = bridge._button(title)
	end
	return apply_layout(button, props)
end

function UI.Toggle(props)
	local label = type(props) == "table" and (props.label or props[1] or "") or ""
	local is_on = type(props) == "table" and props.is_on or false
	local action = type(props) == "table" and props.action or nil
	local toggle
	if action then
		toggle = bridge._toggle(label, is_on, action)
	else
		toggle = bridge._toggle(label, is_on)
	end
	return apply_layout(toggle, props)
end

function UI.Separator(props)
	local v = bridge._create("NSBox")
	v.boxType = 2  -- NSBoxSeparator = 2
	v.fixed_height = 1
	v.flex_grow = 1
	return apply_layout(v, props)
end

function UI.ProgressView(props)
	local v = bridge._create("NSProgressIndicator")
	v.style = 1  -- NSProgressIndicatorStyleSpinning = 1
	v.displayedWhenStopped = false
	return apply_layout(v, props)
end

function UI.Layout(view, props)
	if type(view) ~= "userdata" then
		error("Layout requires a view userdata")
	end
	return apply_layout(view, props)
end

function UI.ProgressStart(progress)
	bridge._perform(progress, "startAnimation:", nil)
end

function UI.ProgressStop(progress)
	bridge._perform(progress, "stopAnimation:", nil)
end

function UI.ToolbarProgress(window, identifier)
	local item = UI.ToolbarItem(window, identifier)
	local restore_view = item.view
	local progress = UI.ProgressView()
	bridge._set_content_size(progress, 32, 32)

	return {
		start = function(self, tooltip)
			if tooltip then item.toolTip = tooltip end
			item.view = progress
			UI.ProgressStart(progress)
		end,
		stop = function(self, tooltip)
			UI.ProgressStop(progress)
			item.view = restore_view
			item.enabled = true
			if tooltip then item.toolTip = tooltip end
		end,
	}
end

UI.Spinner = UI.ProgressView
UI.SpinnerStart = UI.ProgressStart
UI.SpinnerStop = UI.ProgressStop

function UI.sleep(seconds)
	local co = coroutine.running()
	if not co then
		error("sleep() must be called from within a coroutine (use async())")
	end
	bridge._timer_after(seconds, function()
		coroutine.resume(co)
	end)
	coroutine.yield()
end

function UI.async(fn)
	local co = coroutine.create(fn)
	coroutine.resume(co)
end

return UI
