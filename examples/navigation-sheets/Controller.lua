local Navigation = require("ui.navigation")
local xml = require("ui.xml")

local Controller = {}

function Controller.new()
    return setmetatable({
        nav = Navigation.new(),
        showFilter = false,
    }, { __index = Controller })
end

function Controller:showFilter()
    self.showFilter = true
end

function Controller:closeFilter()
    self.showFilter = false
end

function Controller:createWindow()
    local view, refs = xml.renderFile("views/Main.etlua", {
        showFilter = self.showFilter,
        actions = {
            showFilter = function() self:showFilter() end,
            closeFilter = function() self:closeFilter() end,
        },
    }, require("ns"))

    return view, refs
end

return Controller
