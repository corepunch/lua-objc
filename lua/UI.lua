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

    local win = bridge._window(title, width, height)
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

return UI
