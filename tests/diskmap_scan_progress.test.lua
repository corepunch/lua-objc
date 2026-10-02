-- A running scan shows in one small window: a bar that fills with measured
-- bytes over the bytes the disk reports as used, and Stop. The window is
-- rendered once; the controller sets the bar and the status on each tick.
_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Store = require("apps.diskmap.Store")
local Scan = require("apps.diskmap.services.Scan")
local ScanProgress = require("apps.diskmap.controllers.ScanProgressController")

local model = Store.new("/Users/test")
model.measurements = {a = {bytes = 256}, b = {bytes = 256}}
local cancelled = 0
local scan = Scan.new(model, {cancel = function() end}, "/Users/test", function() cancelled = cancelled + 1 end)
scan.disk, scan.status = {totalKb = 1, freeKb = 0}, "Measuring all storage categories…"

t.assertEqual(scan:fraction(), 0.5, "the fraction is bytes measured over bytes used")
model.measurements.c = {bytes = 4096}
t.assertEqual(scan:fraction(), 0.99, "it stays short of full until the scan says it is done")
scan.disk = nil
t.assertEqual(scan:fraction(), nil, "without the disk's used size there is no fraction")
scan.disk = {totalKb = 4, freeKb = 4}
t.assertEqual(scan:fraction(), nil, "nor for a disk that reports nothing used")

scan.disk = {totalKb = 1, freeKb = 0}
model.measurements.c = nil
local window = ns.Window {visible = false, width = 600, height = 400}
local progress = ScanProgress.new(scan)
progress:update()
t.expect(progress.sheet == nil, "updating a closed window does nothing")
progress:show(window)
t.expect(progress.sheet ~= nil, "showing opens the window")
local bar, status = progress.refs.scanBar, progress.refs.scanStatus
t.assertEqual(bar.doubleValue, 0.5, "the bar shows the fraction")
t.expect(not bar.indeterminate, "with a known disk the bar has a length")
t.assertEqual(status.text, "Measuring all storage categories…", "the status line is the scan's")

model.measurements.c = {bytes = 128}
scan.status = "3 of 9 locations measured"
local sheet = progress.sheet
progress:show(window)
t.expect(progress.sheet == sheet and progress.refs.scanBar == bar and progress.refs.scanStatus == status,
	"showing again keeps the window and its views: nothing is rendered again")
t.assertEqual(status.text, "3 of 9 locations measured", "the controller sets the status in place")
t.assertEqual(bar.doubleValue, 0.625, "and moves the bar")

scan.disk = nil
progress:update()
t.expect(bar.indeterminate, "without the disk's used size the bar is of unknown length")
scan.disk = {totalKb = 1, freeKb = 0}
progress:update()
t.expect(not bar.indeterminate and bar.doubleValue == 0.625, "and takes its length back when the size is known")

require("AppKitNative")._invokeAction(progress.refs.scanStop)
t.assertEqual(cancelled, 1, "Stop cancels the scan")
progress:close()
t.expect(progress.sheet == nil and progress.refs == nil, "closing dismisses the window")
progress:close()
os.exit(t.summary() and 0 or 1)
