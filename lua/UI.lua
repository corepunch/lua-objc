local bridge = require("bridge")

local UI = {}

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

	local win = bridge._window(title, width, height,
		transparent_titlebar, hide_title)
	local content = bridge._vstack()
	bridge._set_frame(content, 0, 0, width, height)
	bridge._add(win, content)

	for _, v in ipairs(props) do
		if type(v) == "userdata" then
			bridge._add(content, v)
		end
	end

	bridge._layout(content, width)

	local _, _, cw, ch = bridge._get_frame(content)
	local totalH = math.max(ch, height)
	bridge._set_content_size(win, width, totalH)

	bridge._show(win)
end

function UI.VStack(props)
	local view = bridge._vstack()
	if type(props) == "table" then
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
		for _, v in ipairs(props) do
			if type(v) == "userdata" then
				bridge._add(view, v)
			end
		end
	end
	return view
end

function UI.Text(arg)
	local text
	if type(arg) == "table" then
		text = arg[1] or ""
	elseif type(arg) == "string" then
		text = arg
	else
		text = tostring(arg)
	end
	return bridge._text(text)
end

function UI.Image(arg)
	local path
	if type(arg) == "table" then
		path = arg[1] or ""
	elseif type(arg) == "string" then
		path = arg
	else
		path = tostring(arg)
	end
	return bridge._image(resolve_image(path))
end

function UI.Spacer()
	return bridge._spacer()
end

function UI.List(props)
	local columns = props.columns
	if not columns or type(columns) ~= "table" then
		error("List requires a 'columns' property (array of {id, title})")
	end

	local width = props.width or 400
	local height = props.height or 200

	local tv = bridge._tableview(columns, width, height)

	if props.data and type(props.data) == "table" then
		for _, row in ipairs(props.data) do
			if type(row) == "table" then
				tv:add_row(row)
			end
		end
	end

	return tv
end

function UI.Spinner()
	return bridge._spinner()
end

function UI.SpinnerStart(spinner)
	bridge._spinner_start(spinner)
end

function UI.SpinnerStop(spinner)
	bridge._spinner_stop(spinner)
end

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
