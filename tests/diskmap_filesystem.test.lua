_G.__headless = true
local SimulatorService = require("apps.diskmap.services.Simulators")
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Simulators = require("apps.diskmap.helpers.Simulators")
local Sdks = require("apps.diskmap.helpers.Sdks")
local Discovery = require("apps.diskmap.services.Sdks")

local function writeSnapshot(path, items)
	table.sort(items, function(a, b) return a[1] < b[1] end)
	local records = {}
	for _, item in ipairs(items) do table.insert(records, {path = item[1], allocatedBytes = item[2]}) end
	require("apps.diskmap.services.Scanner").writeSnapshot(path, {capacityBytes = 1000000000000, availableBytes = 400000000000, visited = #items}, records)
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
local unnamed = SimulatorService.discover(mock, home)
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
mock.readPropertyList = ns.readPropertyList
local named = SimulatorService.discover(mock, home)
local namedDevice = named.devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"][1]
t.assertEqual(namedDevice.name, "iPhone 17", "device.plist supplies the simulator name")
t.assertEqual(Simulators.rows(named)[1].runtime, "iOS 26.0", "runtime identifier becomes a version label")
t.assertEqual(Simulators.rows(named, nil, os.time({year = 2026, month = 9, day = 25, hour = 12}))[1].lastUse, "Used 5 days ago", "last use comes from device.plist")
t.assertEqual(namedDevice.dataPathSize, 5000000000, "plist metadata does not replace the snapshot size")

local xcode = Discovery.discover(mock, "/Applications/Xcode.app")
t.assertEqual(#xcode, 2, "Xcode review lists SDK bundles inside that installation")
t.assertEqual(xcode[1].name, "iPhoneOS", "largest SDK is listed first")
t.assertEqual(xcode[1].platform, "iOS", "iPhoneOS SDK is labeled iOS")
t.assertEqual(xcode[1].bytes, 800000000, "SDK size includes the bundle contents")
t.assertEqual(xcode[2].name, "MacOSX", "MacOSX SDK is listed beside iPhoneOS")
t.assertEqual(xcode[2].platform, "macOS", "MacOSX SDK is labeled macOS")
local tools = Discovery.discover(mock, "/Library/Developer/CommandLineTools")
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
