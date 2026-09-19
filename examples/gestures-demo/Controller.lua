local xml = require("ui.xml")
local haptics = require("ui.haptics")

local Controller = {}

function Controller.new()
    return setmetatable({
        tapCount = 0,
        longPressCount = 0,
        dragCount = 0,
        gestureLog = {},
    }, { __index = Controller })
end

function Controller:log(message)
    table.insert(self.gestureLog, os.date("%H:%M:%S") .. " — " .. message)
    if #self.gestureLog > 10 then
        table.remove(self.gestureLog, 1)
    end
end

function Controller:handleTap()
    self.tapCount = self.tapCount + 1
    haptics.impact("light")
    self:log("Tapped (" .. self.tapCount .. "x)")
    self:updateUI()
end

function Controller:handleLongPress()
    self.longPressCount = self.longPressCount + 1
    haptics.impact("heavy")
    self:log("Long pressed (" .. self.longPressCount .. "x)")
    self:updateUI()
end

function Controller:handleDrag()
    self.dragCount = self.dragCount + 1
    haptics.selection()
    self:log("Dragged (" .. self.dragCount .. "x)")
    self:updateUI()
end

function Controller:handleSuccess()
    haptics.notification("success")
    self:log("Success feedback")
    self:updateUI()
end

function Controller:handleWarning()
    haptics.notification("warning")
    self:log("Warning feedback")
    self:updateUI()
end

function Controller:handleError()
    haptics.notification("error")
    self:log("Error feedback")
    self:updateUI()
end

function Controller:resetCounts()
    self.tapCount = 0
    self.longPressCount = 0
    self.dragCount = 0
    self.gestureLog = {}
    haptics.tap()
    self:log("Counters reset")
    self:updateUI()
end

function Controller:updateUI()
    -- This would update the UI refs in a real implementation
end

function Controller:createWindow()
    local view, refs = xml.renderFile("views/Main.etlua", {
        tapCount = self.tapCount,
        longPressCount = self.longPressCount,
        dragCount = self.dragCount,
        gestureLog = self.gestureLog,
        actions = {
            tap = function() self:handleTap() end,
            longPress = function() self:handleLongPress() end,
            drag = function() self:handleDrag() end,
            success = function() self:handleSuccess() end,
            warning = function() self:handleWarning() end,
            error = function() self:handleError() end,
            reset = function() self:resetCounts() end,
        },
    }, require("ns"))

    return view, refs
end

return Controller
