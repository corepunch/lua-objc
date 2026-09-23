--[[
  ui/navigation.lua — Data-driven navigation with sheets and presentation detents

  Manages navigation stacks, sheet presentation, and destination routing.

  Usage:
    local nav = Navigation.new()
    nav:push("DetailView", { itemId = 42 })
    nav:presentSheet("Filter", { detents = { "medium", "large" } })
]]

local Navigation = {}
Navigation.__index = Navigation

-- Value path shared by NavigationStack adapters. Values are plain model data;
-- builders stay in the controller/UI layer and resolve by `type` or string key.
local Path = {}
Path.__index = Path

function Path.new(values)
    local path = setmetatable({ values = {}, destinations = {}, observers = {} }, Path)
    for _, value in ipairs(values or {}) do path.values[#path.values + 1] = value end
    return path
end

local function valueType(value)
    if type(value) == "table" then return value.type or value.kind end
    return type(value) == "string" and value or nil
end

function Path:registerDestination(kind, builder)
    assert(type(kind) == "string" and kind ~= "", "destination type must be a non-empty string")
    assert(type(builder) == "function", "destination builder must be a function")
    self.destinations[kind] = builder
end

function Path:destination(value)
    local kind = valueType(value)
    return kind and self.destinations[kind] or nil
end

function Path:observe(callback)
    assert(type(callback) == "function", "path observer must be a function")
    self.observers[#self.observers + 1] = callback
    return function()
        for i, observer in ipairs(self.observers) do
            if observer == callback then table.remove(self.observers, i); break end
        end
    end
end

function Path:_notify(action, value)
    for _, callback in ipairs(self.observers) do callback(action, value, self) end
end

function Path:push(value)
    assert(value ~= nil, "navigation path cannot contain nil")
    self.values[#self.values + 1] = value
    self:_notify("push", value)
end

function Path:pop()
    if #self.values == 0 then return nil end
    local value = table.remove(self.values)
    self:_notify("pop", value)
    return value
end

function Path:replace(value)
    assert(value ~= nil, "navigation path cannot contain nil")
    local action = #self.values == 0 and "push" or "replace"
    if action == "push" then self.values[1] = value
    else self.values[#self.values] = value end
    self:_notify(action, value)
end

function Path:reset(values)
    self.values = {}
    for _, value in ipairs(values or {}) do self.values[#self.values + 1] = value end
    self:_notify("reset", self:valuesCopy())
end

function Path:current() return self.values[#self.values] end
function Path:count() return #self.values end
function Path:valuesCopy()
    local values = {}
    for i, value in ipairs(self.values) do values[i] = value end
    return values
end

Navigation.Path = Path

-- Connect a value path to platform push/pop operations. Values resolve only
-- through registered controller builders; domain values never become views.
function Navigation.bindPath(path, pushScreen, popScreen)
    assert(getmetatable(path) == Path, "bindPath requires Navigation.Path")
    assert(type(pushScreen) == "function" and type(popScreen) == "function",
        "bindPath requires native push and pop operations")
    local mounted = {}
    local function pushValue(value)
        local builder = path:destination(value)
        assert(builder, "no navigation destination registered for " .. tostring(valueType(value)))
        pushScreen(value, builder)
        mounted[#mounted + 1] = value
    end
    local function popValue()
        if #mounted == 0 then return end
        popScreen()
        table.remove(mounted)
    end
    local removeObserver = path:observe(function(action, value)
        if action == "push" then pushValue(value)
        elseif action == "pop" then popValue()
        elseif action == "replace" then popValue(); pushValue(value)
        elseif action == "reset" then
            while #mounted > 0 do popValue() end
            for _, item in ipairs(value) do pushValue(item) end
        end
    end)
    for _, value in ipairs(path.values) do pushValue(value) end
    return removeObserver
end

function Navigation.new()
    return setmetatable({
        stack = {},
        sheetStack = {},
        destinations = {},
        presented = {},
        zoom = {},
    }, Navigation)
end

-- Register a destination handler
function Navigation:registerDestination(name, handler)
    self.destinations[name] = handler
end

-- Push onto navigation stack
function Navigation:push(destinationName, data)
    table.insert(self.stack, {
        name = destinationName,
        data = data or {},
    })
end

-- Pop from navigation stack
function Navigation:pop()
    if #self.stack > 1 then
        table.remove(self.stack)
    end
end

-- Present sheet
function Navigation:presentSheet(sheetName, options)
    table.insert(self.sheetStack, {
        name = sheetName,
        detents = options.detents or { "large" },
        dragIndicator = options.dragIndicator ~= false,
    })
end

-- Dismiss sheet
function Navigation:dismissSheet()
    if #self.sheetStack > 0 then
        table.remove(self.sheetStack)
    end
end

-- Get current screen
function Navigation:current()
    return self.stack[#self.stack]
end

-- Get current sheet
function Navigation:currentSheet()
    return self.sheetStack[#self.sheetStack]
end

-- Boolean navigationDestination(isPresented:) from the SwiftUI zoom recipe.
function Navigation:registerPresented(name, handler, opts)
    opts = opts or {}
    self.destinations[name] = handler
    self.presented[name] = false
    self.zoom[name] = {
        sourceId = opts.sourceId,
        namespace = opts.namespace,
        transition = opts.transition or "zoom",
    }
end

function Navigation:setPresented(name, isPresented)
    local was = self.presented[name]
    self.presented[name] = isPresented and true or false
    if was ~= self.presented[name] then
        if self.presented[name] then
            local zoom = self.zoom[name] or {}
            self:push(name, {
                sourceId = zoom.sourceId,
                namespace = zoom.namespace,
                transition = zoom.transition,
            })
        else
            self:pop()
        end
    end
    return self.presented[name]
end

function Navigation:isPresented(name)
    return self.presented[name] == true
end

-- Push vs Replace (one-way door)
function Navigation:replace(destinationName, data)
    if #self.stack > 0 then
        self.stack[#self.stack] = {
            name = destinationName,
            data = data or {},
        }
    else
        self:push(destinationName, data)
    end
end

return Navigation
