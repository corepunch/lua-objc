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

function Navigation.new()
    return setmetatable({
        stack = {},
        sheetStack = {},
        destinations = {},
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
