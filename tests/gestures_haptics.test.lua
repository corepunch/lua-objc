local function testHapticsModule()
    _G.__headless = true
    package.path = "./?.lua;" .. package.path

    local haptics = require("ui.haptics")

    -- Test 1: Impact haptics
    haptics.impact("light")
    haptics.impact("medium")
    haptics.impact("heavy")
    print("✓ Impact haptics")

    -- Test 2: Selection haptics
    haptics.selection()
    print("✓ Selection haptics")

    -- Test 3: Notification haptics
    haptics.notification("success")
    haptics.notification("warning")
    haptics.notification("error")
    print("✓ Notification haptics")

    -- Test 4: Convenience methods
    haptics.tap()
    print("✓ Tap convenience")

    haptics.confirm()
    print("✓ Confirm convenience")

    haptics.reject()
    print("✓ Reject convenience")

    -- Test 5: Availability check
    local available = haptics.isAvailable()
    -- Should return true or false without crashing
    print("✓ Availability check: " .. tostring(available))

    -- Test 6: Sequence
    haptics.sequence({
        { 0.05, "light" },
        { 0.1, nil },
        { 0.05, "medium" },
    })
    print("✓ Haptics sequence")

    -- Test 7: Empty sequence (should not crash)
    haptics.sequence({})
    print("✓ Empty sequence")

    -- Test 8: Nil sequence (should not crash)
    haptics.sequence(nil)
    print("✓ Nil sequence")

    print("\nAll haptics tests passed!")
    return true
end

os.exit(testHapticsModule() and 0 or 1)
