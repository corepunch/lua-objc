local xml = require("ui.xml")

local Controller = {}

function Controller.new()
    return setmetatable({
        items = {
            { id = 1, title = "First item", completed = false },
            { id = 2, title = "Second item", completed = false },
            { id = 3, title = "Third item", completed = false },
        },
    }, { __index = Controller })
end

function Controller:archiveItem(id)
    for i, item in ipairs(self.items) do
        if item.id == id then
            table.remove(self.items, i)
            break
        end
    end
end

function Controller:deleteItem(id)
    for i, item in ipairs(self.items) do
        if item.id == id then
            table.remove(self.items, i)
            break
        end
    end
end

function Controller:markComplete(id)
    for _, item in ipairs(self.items) do
        if item.id == id then
            item.completed = not item.completed
            break
        end
    end
end

function Controller:createWindow()
    local view, refs = xml.renderFile("views/Main.etlua", {
        items = self.items,
        actions = {
            archive = function(id) self:archiveItem(id) end,
            delete = function(id) self:deleteItem(id) end,
            complete = function(id) self:markComplete(id) end,
        },
    }, require("ns"))

    return view, refs
end

return Controller
