_G.__headless = true

local t = require("TestKit")
local Controller = require("apps.glass-materials.Controller")
local Model = require("apps.glass-materials.Model")

local model = Model.new()
t.assertEqual(model.materials[1].value, "regular", "regular glass is available")
t.assertEqual(model.materials[2].value, "clear", "clear glass is available")

local controller = Controller.new()
local ok, window = pcall(function() return controller:createWindow() end)
t.expect(ok and window ~= nil, "glass example constructs its native window headlessly")
if not ok then io.stderr:write(tostring(window) .. "\n") end

os.exit(t.summary() and 0 or 1)
