-- UIKitNative is registered by the host before this layer runs.
local bridge = require("UIKitNative")
local UIKit = bridge

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

function UIKit.Window(props)
	props = props or {}
	local content = props.content or props[1]
	local vc = asViewController(content)
	return bridge._installScene(vc, props.title or "")
end

function UIKit.TabView(props)
	local tbc = bridge._tabview()
	local tabs = props.tabs or {}
	for _, tab in ipairs(tabs) do
		if type(tab) == "table" and tab.__tab then
			local vc = asViewController(tab.content)
			bridge._tabViewAddTab(tbc, vc, tab.title or "", tab.systemImage or "")
		end
	end
	return tbc
end

function UIKit.HostingController(view)
	return bridge._hostingController(view)
end

function UIKit.NavigationStack(props)
	props = props or {}
	local content = props.content or props[1]
	return bridge._navigationStack(asViewController(content))
end

function UIKit.VStack(props)
	local view = bridge._vstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

function UIKit.HStack(props)
	local view = bridge._hstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

function UIKit.ZStack(props)
	local view = bridge._zstack()
	if type(props) == "table" then
		applyLayout(view, props)
		addChildren(view, props)
	end
	return view
end

function UIKit.ScrollView(props)
	assert(type(props) == "table", "ScrollView requires a property table")
	local content = props.content or props[1]
	assert(type(content) == "userdata", "ScrollView requires one content view")
	return applyLayout(bridge._scrollView(content, props.contentWidth or 0,
		props.contentHeight or 0, props.horizontal == true, props.vertical ~= false), props)
end

function UIKit.TextField(arg)
	local text = ""
	local props
	if type(arg) == "table" then
		text = arg[1] or arg.placeholder or arg.value or ""
		props = arg
	elseif type(arg) == "string" then
		text = arg
	end
	local v = bridge._textField(text)
	return applyLayout(v, props)
end

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

function UIKit.Title(arg)
	return UIKit.Label({
		type(arg) == "table" and (arg[1] or arg.text) or arg,
		size = 22,
		weight = "bold",
	})
end

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

function UIKit.Spacer(props)
	return applyLayout(bridge._spacer(), props)
end

function UIKit.PageControl(props)
	props = props or {}
	return applyLayout(bridge._pageControl(props.numberOfPages or props.pages or 0,
		props.currentPage or 0), props)
end

function UIKit.LinearGradient(props)
	props = props or {}
	return applyLayout(bridge._linearGradient(props.topAlpha or 0,
		props.middleAlpha or 0.5, props.middleLocation or 0.6,
		props.bottomAlpha or 0.82), props)
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
	return applyLayout(tv, props)
end

function UIKit.Button(props)
	local title = type(props) == "table" and (props.title or props[1] or "") or ""
	local action = type(props) == "table" and props.action or nil
	local button
	local style = type(props) == "table" and props.style or nil
	if action then
		button = bridge._button(title, action, style or "default")
	else
		button = bridge._button(title, nil, style or "default")
	end
	if type(props) == "table" and props.truncation then
		local modes = { head = 3, tail = 4, middle = 5 }
		button.titleLabel.lineBreakMode = modes[props.truncation] or 4
		button.titleLabel.numberOfLines = 1
	end
	return applyLayout(button, props)
end

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
	return applyLayout(toggle, props)
end

function UIKit.Separator(props)
	return applyLayout(bridge._separator(), props)
end

UIKit.Divider = UIKit.Separator

function UIKit.ProgressView(props)
	return applyLayout(bridge._progressIndicator(), props)
end

function UIKit.Group(children)
	children = children or {}
	children.__appkitGroup = true
	return children
end

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
