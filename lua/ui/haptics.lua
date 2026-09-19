--[[
  ui/haptics.lua — Haptic feedback utilities

  Wrapper around native haptic feedback (Taptic Engine on iOS,
  trackpad on macOS). All haptics run asynchronously and do not block.

  Usage:
    local haptics = require("ui.haptics")
    haptics.impact("light")
    haptics.notification("success")
]]

local M = {}

-- Check if reduce motion is enabled (user preference)
local function isReduceMotionEnabled()
    local ok, bridge = pcall(require, "UIKitNative")
    if ok and type(bridge._reduceMotionEnabled) == "function" then
        return bridge._reduceMotionEnabled()
    end
    ok, bridge = pcall(require, "AppKitNative")
    if ok and type(bridge._reduceMotionEnabled) == "function" then
        return bridge._reduceMotionEnabled()
    end
    return false
end

-- Get native haptics provider
local function getNativeHaptics()
    local ok, bridge = pcall(require, "UIKitNative")
    if ok and type(bridge._haptics) == "table" then
        return bridge._haptics
    end
    ok, bridge = pcall(require, "AppKitNative")
    if ok and type(bridge._haptics) == "table" then
        return bridge._haptics
    end
    return nil
end

--[[ Impact Haptics

Provide tactile feedback with varying intensities.
Intensity levels:
  - "light": 17 (selection)
  - "medium": 33 (interaction)
  - "heavy": 50 (impact)
]]
function M.impact(intensity)
    intensity = intensity or "medium"

    if isReduceMotionEnabled() then
        return  -- Respect user preference
    end

    local haptics = getNativeHaptics()
    if haptics and type(haptics.impact) == "function" then
        haptics.impact(intensity)
    end
end

--[[ Selection Haptics

Provide feedback when user moves through selectable options
(e.g., picker, slider). Call each time the selection changes.
]]
function M.selection()
    if isReduceMotionEnabled() then
        return
    end

    local haptics = getNativeHaptics()
    if haptics and type(haptics.selection) == "function" then
        haptics.selection()
    end
end

--[[ Notification Haptics

Provide feedback for completion or error states.
Types:
  - "success": Three ascending tones
  - "warning": Two warning tones
  - "error": Sharp, heavy impact
]]
function M.notification(notificationType)
    notificationType = notificationType or "success"

    if isReduceMotionEnabled() then
        return
    end

    local haptics = getNativeHaptics()
    if haptics and type(haptics.notification) == "function" then
        haptics.notification(notificationType)
    end
end

--[[ Pattern: Light press

Convenience for common "light tap" feedback.
Equivalent to impact("light").
]]
function M.tap()
    M.impact("light")
end

--[[ Pattern: Confirmation

Heavy impact with success notification.
Used for important confirmations (delete, submit).
]]
function M.confirm()
    M.impact("heavy")
    M.notification("success")
end

--[[ Pattern: Rejection

Warn with error notification.
Used when an action is invalid or fails.
]]
function M.reject()
    M.impact("heavy")
    M.notification("error")
end

--[[ Check if haptics are available

Returns true if the device supports haptics.
Useful for graceful degradation.
]]
function M.isAvailable()
    local haptics = getNativeHaptics()
    return haptics ~= nil
end

--[[ Perform a sequence of haptics

Chain multiple haptic patterns for complex feedback.
Each entry is { duration, intensity } where:
  - duration: time in seconds (e.g., 0.1)
  - intensity: "light", "medium", "heavy" or notification type

Example:
  haptics.sequence({
    { 0.05, "light" },
    { 0.1, nil },      -- 100ms pause
    { 0.05, "medium" },
  })

Note: Pauses are simulated; all haptics queue asynchronously.
]]
function M.sequence(patterns)
    if isReduceMotionEnabled() or not M.isAvailable() then
        return
    end

    if not patterns or #patterns == 0 then
        return
    end

    -- Queue each pattern with timing
    local elapsed = 0
    for i, pattern in ipairs(patterns) do
        local duration = pattern[1] or 0.05
        local intensity = pattern[2]

        if intensity then
            -- Schedule haptic callback
            -- For now, queue them immediately (native layer handles timing)
            if intensity == "success" or intensity == "warning" or intensity == "error" then
                M.notification(intensity)
            else
                M.impact(intensity)
            end
        end

        elapsed = elapsed + duration
    end
end

return M
