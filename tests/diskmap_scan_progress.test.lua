-- A running scan shows in one small window: a bar that fills with measured
-- bytes over the bytes the disk reports as used, and Stop.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Core = require("apps.diskmap.Model")
local ScanProgress = require("apps.diskmap.models.ScanProgress")

local model = Core.new("/Users/test")
model.measurements = {a = {bytes = 256}, b = {bytes = 256}}
local disk, status, cancelled = {totalKb = 1, freeKb = 0}, "Measuring all storage categories…", 0
local progress = ScanProgress.new({}, {model = model, scanDisk = function() return disk end,
	scanStatus = function() return status end, cancelScan = function() cancelled = cancelled + 1 end})

t.assertEqual(progress:data().fraction, 0.5, "the bar is bytes measured over bytes used")
t.expect(not progress:data().indeterminate, "with a known disk the bar has a length")
model.measurements.c = {bytes = 4096}
t.assertEqual(progress:data().fraction, 0.99, "it stays short of full until the scan says it is done")
disk = nil
t.expect(progress:data().indeterminate, "without the disk's used size the bar is of unknown length")
t.assertEqual(progress:data().status, status, "the status line is the scan's")

disk = {totalKb = 1, freeKb = 0}
model.measurements.c = nil
local window = ns.Window {visible = false, width = 600, height = 400}
progress:show(window)
t.expect(progress.sheet ~= nil, "showing opens the window")
t.assertEqual(progress.refs.scanBar.doubleValue, 0.5, "the bar shows the fraction")
model.measurements.c = {bytes = 128}
status = "3 of 9 locations measured"
progress:show(window)
t.assertEqual(progress.refs.scanStatus.text, status, "showing again updates it in place")
t.assertEqual(progress.refs.scanBar.doubleValue, 0.625, "and moves the bar")
progress.body.actions.stop()
t.assertEqual(cancelled, 1, "Stop cancels the scan")
progress:close()
t.expect(progress.sheet == nil, "closing dismisses the window")
os.exit(t.summary() and 0 or 1)
