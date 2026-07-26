-- UIKitNative is registered by UIKit.dylib before this embedded layer runs.
local bridge = require("UIKitNative")

local UIKit = {}

-- coroutine.resume reports failures as return values. Always surface those
-- failures because timers and network callbacks otherwise swallow Lua errors.
local function resumeCoroutine(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		io.stderr:write("coroutine error: " .. tostring(err) .. "\n")
	end
	return ok, err
end

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

function UIKit.Window(props)
	local title = props.title or "Window"
	local width = props.width or 480
	local height = props.height or 360

	local win = bridge._window(title, width, height, false, false)
	bridge._setContentSize(win, width, height)

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

function UIKit.VStack(props)
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

function UIKit.HStack(props)
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

function UIKit.TextField(arg)
	local text = ""
	local props
	if type(arg) == "table" then
		text = arg[1] or arg.placeholder or ""
		props = arg
	elseif type(arg) == "string" then
		text = arg
	end

	local v = bridge._create("UITextField")
	if text ~= "" then v.text = text end
	return applyLayout(v, props)
end

function UIKit.Label(arg)
	local text
	local props
	if type(arg) == "table" then
		text = arg[1] or ""
		props = arg
	elseif type(arg) == "string" then
		text = arg
	else
		text = tostring(arg)
	end

	local v = bridge._create("UILabel")
	v.text = text
	v.numberOfLines = 0
	bridge._perform(v, "sizeToFit")
	return applyLayout(v, props)
end

function UIKit.ImageView(arg)
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

function UIKit.Spacer(props)
	return applyLayout(bridge._spacer(), props)
end

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

function UIKit.Button(props)
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

function UIKit.Switch(props)
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

function UIKit.Separator(props)
	local v = bridge._create("UIView")
	v.fixedHeight = 1
	v.flexGrow = 1
	return applyLayout(v, props)
end

function UIKit.ProgressView(props)
	local v = bridge._create("UIActivityIndicatorView")
	bridge._perform(v, "startAnimating")
	return applyLayout(v, props)
end

UIKit.Text = UIKit.Label

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
