local Model = require("Model")
local xml = require("ui.xml")

local Controller = {}

function Controller.new()
    return setmetatable({
        model = Model.new(),
    }, { __index = Controller })
end

function Controller:createWindow()
    local view, refs = xml.renderFile("apps/glass-materials/views/Main.etlua", {
        materials = self.model.materials,
        selectedMaterial = self.model.selectedMaterial,
        isMinimizedOnScroll = self.model.isMinimizedOnScroll,
        actions = {
            selectMaterial = function(value)
                self.model.selectedMaterial = value
            end,
            toggleMinimized = function(enabled)
                self.model.isMinimizedOnScroll = enabled
            end,
        },
    }, require("ns"))

    return view, refs
end

return Controller
