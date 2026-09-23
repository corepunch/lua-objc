-- Native haptic feedback and the platform Reduce Motion preference.
local M = {}
local testEnvironment

local function nativeBridge()
	for _, name in ipairs({ "UIKitNative", "AppKitNative" }) do
		local ok, bridge = pcall(require, name)
		if ok and type(bridge._hapticImpact) == "function" then return bridge end
	end
	return nil
end

function M.isReduceMotionEnabled()
	if testEnvironment then return testEnvironment.reduceMotion end
	local bridge = nativeBridge()
	return bridge ~= nil and bridge._reduceMotionEnabled() or false
end

local function request(method, ...)
	if M.isReduceMotionEnabled() then return false end
	if testEnvironment then
		table.insert(testEnvironment.requests, { method, ... })
		return true
	end
	local bridge = nativeBridge()
	if not bridge or not bridge._hapticsAvailable() then return false end
	bridge[method](...)
	return true
end

function M.impact(intensity)
	return request("_hapticImpact", intensity or "medium")
end

function M.selection()
	return request("_hapticSelection")
end

function M.notification(kind)
	return request("_hapticNotification", kind or "success")
end

function M.tap() return M.impact("light") end
function M.confirm()
	M.impact("heavy")
	M.notification("success")
end
function M.reject()
	M.impact("heavy")
	M.notification("error")
end

function M.isAvailable()
	if testEnvironment then return testEnvironment.available end
	local bridge = nativeBridge()
	return bridge ~= nil and bridge._hapticsAvailable() or false
end

-- Private test hook: verifies native requests and Reduce Motion without
-- requiring a physical haptic engine.
function M._setTestEnvironment(reduceMotion, available)
	if reduceMotion == nil then testEnvironment = nil; return end
	testEnvironment = {
		reduceMotion = reduceMotion == true,
		available = available ~= false,
		requests = {},
	}
	return testEnvironment.requests
end

return M
