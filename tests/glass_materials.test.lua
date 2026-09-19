local function createController()
    _G.__headless = true
    package.path = "./examples/glass-materials/?.lua;" .. package.path
    local Controller = require("Controller")
    return Controller.new()
end

function testGlassMaterialsRender()
    local controller = createController()
    local view = controller:createWindow()
    assert(view ~= nil, "Should render window")
end

function testMaterialSelection()
    local controller = createController()

    -- Verify initial material
    assert(controller.model.selectedMaterial == "regular")

    -- Simulate selection
    controller.model.selectedMaterial = "ultraThin"
    assert(controller.model.selectedMaterial == "ultraThin")
end

function testToolbarMinimizeToggle()
    local controller = createController()

    -- Verify initial state
    assert(controller.model.isMinimizedOnScroll == true)

    -- Simulate toggle
    controller.model.isMinimizedOnScroll = false
    assert(controller.model.isMinimizedOnScroll == false)
end

function testMaterialsList()
    local controller = createController()
    local materials = controller.model.materials

    assert(#materials == 5, "Should have 5 material options")
    assert(materials[1].value == "ultraThin")
    assert(materials[5].value == "ultraThick")
end

print("Glass & Materials Tests")
testGlassMaterialsRender()
testMaterialSelection()
testToolbarMinimizeToggle()
testMaterialsList()
print("✓ All tests passed")
