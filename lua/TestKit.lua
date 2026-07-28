local bridge = require("bridge")

local TestKit = {}

local failed = 0
local passed = 0

function TestKit.expect(condition, message)
	if condition then
		passed = passed + 1
		return true
	end
	failed = failed + 1
	io.stderr:write(string.format("FAIL: %s\n", message or "expectation failed"))
	return false
end

function TestKit.assertEqual(actual, expected, message)
	message = message or ("assertEqual: expected " .. tostring(expected) .. ", got " .. tostring(actual))
	if actual == expected then
		passed = passed + 1
		return true
	end
	failed = failed + 1
	io.stderr:write("FAIL: " .. message .. "\n")
	return false
end

function TestKit.assertHasKey(table, key, message)
	message = message or ("assertHasKey: key '" .. tostring(key) .. "' not found")
	if table[key] ~= nil then
		passed = passed + 1
		return true
	end
	failed = failed + 1
	io.stderr:write("FAIL: " .. message .. "\n")
	return false
end

function TestKit.assertSize(view, width, height, message)
	message = message or "assertSize"
	local size = view.size
	local fw, fh = size.width, size.height
	if fw == width and fh == height then
		passed = passed + 1
		return true
	end
	failed = failed + 1
	io.stderr:write(string.format(
		"FAIL: %s: expected %.0fx%.0f, got %.0fx%.0f\n",
		message, width, height, fw, fh))
	return false
end

function TestKit.assertThrows(fn, message)
	message = message or "assertThrows: expected error"
	local ok, err = pcall(fn)
	if not ok then
		passed = passed + 1
		return true, err
	end
	failed = failed + 1
	io.stderr:write("FAIL: " .. message .. "\n")
	return false
end

function TestKit.summary()
	local total = passed + failed
	io.write(string.format("\n%d passed, %d failed, %d total\n",
		passed, failed, total))
	return failed == 0
end

function TestKit.reset()
	passed = 0
	failed = 0
end

return TestKit
