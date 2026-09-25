_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Simulators = require("apps.diskmap.models.Simulators")
local Sdks = require("apps.diskmap.models.Sdks")

local function u32(n)
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function u64(n)
	return u32(n % 4294967296) .. u32(math.floor(n / 4294967296))
end
local function writeSnapshot(path, items)
	table.sort(items, function(a, b) return a[1] < b[1] end)
	local body, previous = {}, ""
	for _, item in ipairs(items) do
		local shared = 0
		while shared < #previous and shared < #item[1] and previous:sub(shared + 1, shared + 1) == item[1]:sub(shared + 1, shared + 1) do
			shared = shared + 1
		end
		local suffix = item[1]:sub(shared + 1)
		table.insert(body, u32(shared) .. u32(#suffix) .. u64(item[2]) .. u64(item[2]) .. suffix)
		previous = item[1]
	end
	local header = "DMOCK001" .. u32(1) .. u32(0) .. u64(1000000000000) .. u64(400000000000) .. u64(#items) .. u64(0) .. u64(#items)
	local file = assert(io.open(path, "wb"))
	file:write(header .. table.concat(body))
	file:close()
end

local home = "/tmp/diskmap-fs-test"
local snapshot = home .. "/fixture.bin"
os.execute("rm -rf " .. home .. " && mkdir -p " .. home)
local device = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
writeSnapshot(snapshot, {
	{"~/Library/Developer/CoreSimulator/Devices/" .. device .. "/data/Containers/app", 5000000000},
	{"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib", 800000000},
	{"/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib", 340000000},
	{"/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk/usr/include", 320000000},
	{"/opt/homebrew/Library/Homebrew/test/support/fixtures/sdks/big_sur/MacOSX.sdk/usr", 1000},
})
local mock = Mock.new({home = home, fixturePath = snapshot})
local unnamed = Simulators.discover(mock, home)
local devices = unnamed.devices.unknown
t.assertEqual(devices and #devices or 0, 1, "a snapshot without simctl metadata still lists the device folder")
t.assertEqual(devices[1].name, device, "a device without device.plist keeps its folder name")
t.assertEqual(devices[1].dataPathSize, 5000000000, "device size is the folder total from the snapshot")

local plistDirectory = home .. "/Library/Developer/CoreSimulator/Devices/" .. device
os.execute("mkdir -p " .. plistDirectory)
local plist = assert(io.open(plistDirectory .. "/device.plist", "w"))
plist:write([[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>name</key><string>iPhone 17</string>
<key>runtime</key><string>com.apple.CoreSimulator.SimRuntime.iOS-26-0</string>
<key>lastBootedAt</key><date>2026-09-20T16:20:00Z</date>
</dict></plist>
]])
plist:close()
local named = Simulators.discover(mock, home)
local namedDevice = named.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"][1]
t.assertEqual(namedDevice.name, "iPhone 17", "device.plist supplies the simulator name")
t.assertEqual(Simulators.rows(named)[1].runtime, "iOS 26.0", "runtime identifier becomes a version label")
t.expect(Simulators.rows(named)[1].lastUse:find("2026-09-20", 1, true) ~= nil, "last use comes from device.plist")
t.assertEqual(namedDevice.dataPathSize, 5000000000, "plist metadata does not replace the snapshot size")

local xcode = Sdks.discover(mock, "/Applications/Xcode.app")
t.assertEqual(#xcode, 2, "Xcode review lists SDK bundles inside that installation")
t.assertEqual(xcode[1].name, "iPhoneOS", "largest SDK is listed first")
t.assertEqual(xcode[1].platform, "iOS", "iPhoneOS SDK is labeled iOS")
t.assertEqual(xcode[1].bytes, 800000000, "SDK size includes the bundle contents")
t.assertEqual(xcode[2].name, "MacOSX", "MacOSX SDK is listed beside iPhoneOS")
t.assertEqual(xcode[2].platform, "macOS", "MacOSX SDK is labeled macOS")
local tools = Sdks.discover(mock, "/Library/Developer/CommandLineTools")
t.assertEqual(#tools, 1, "Command Line Tools review lists its own SDKs")
t.assertEqual(tools[1].name, "MacOSX26", "versioned SDK directories keep their name")
t.assertEqual(tools[1].platform, "Command Line Tools", "Command Line Tools SDKs name their installation")
t.assertEqual(#Sdks.filter(xcode, "iphone"), 1, "SDK search matches the bundle name")
t.assertEqual(#Sdks.filter(xcode, "homebrew"), 0, "SDK review stays inside the selected installation")

local parsed = ns.readPropertyList(plistDirectory .. "/device.plist")
t.assertEqual(parsed.name, "iPhone 17", "property list reader returns the device name")
t.expect(ns.readPropertyList(plistDirectory .. "/missing.plist") == nil, "a missing property list is absent")
os.execute("rm -rf " .. home)
os.exit(t.summary() and 0 or 1)
