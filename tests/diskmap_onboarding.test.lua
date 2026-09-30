_G.__headless = true
local t = require("TestKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Overview = require("apps.diskmap.models.Overview")

-- First launch without Full Disk Access explains it before the first scan
-- and continues by itself once access is granted (#52).
local service = Mock.new()
local granted, opened, relaunched = false, {}, false
service.hasFullDiskAccess = function() return granted end
service.openSettings = function(section) table.insert(opened, section) end
service.relaunch = function() relaunched = true end
local app = Controller.new(service)
app:createWindow()
local onboarding = app.onboarding
t.expect(onboarding.sheet ~= nil, "a first launch without access shows the onboarding sheet")
t.expect(app.model.scan.completedAt == nil, "the first scan waits for the person")
t.expect(onboarding.refs.waiting.hidden and onboarding.refs.restart.hidden, "the waiting status and Restart button appear only after opening Settings")
onboarding:openSettings()
t.assertEqual(opened[1], "privacy", "Open System Settings goes to Full Disk Access")
t.expect(not onboarding.refs.waiting.hidden and not onboarding.refs.restart.hidden, "after Settings opens, Diskmap waits and offers a restart")
t.expect(onboarding:restart() and relaunched, "Restart Diskmap starts a new instance")
t.expect(not onboarding:poll(), "nothing happens while access is still off")
t.expect(onboarding.sheet ~= nil, "the sheet stays while waiting")
granted = true
t.expect(onboarding:poll(), "granting access is noticed")
t.expect(onboarding.sheet == nil, "the sheet closes by itself")
t.expect(app.model.scan.completedAt ~= nil, "the first scan starts without a second click")
t.expect(service.loadFlag("onboarded"), "onboarding is shown once")
local again = Controller.new(service)
again:createWindow()
t.expect(again.onboarding.sheet == nil, "a later launch goes straight to the scan")

-- Continuing without access scans at once; the Overview then names the
-- folders it could not read.
local declined = Mock.new()
declined.hasFullDiskAccess = function() return false end
local other = Controller.new(declined)
other:createWindow()
other.onboarding:finish(false)
t.expect(other.onboarding.sheet == nil and other.model.scan.completedAt ~= nil, "Continue Without Access scans at once")
t.assertEqual(other:state().fullDiskAccess, false, "the missing access is known after the scan")
local home = declined.home
local issues = {}
for index = 1, 8 do table.insert(issues, {path = home .. "/Library/Protected " .. index, reason = "Operation not permitted"}) end
table.insert(issues, {path = home .. "/Library/Protected 1", reason = "Operation not permitted"})
other.model.scan.issues = issues
other:show("overview", true)
local notice = other.pages.overview.notMeasured.refs
t.expect(notice.unmeasured_privacy ~= nil and notice.grantAccess ~= nil, "the Overview shows which folders need Full Disk Access")
local card = Overview.unmeasured(other.model, other:state().disk, {fullDiskAccess = false})
local privacy
for _, item in ipairs(card.items) do if item.id == "privacy" then privacy = item end end
t.assertEqual(privacy.more, "and 2 more", "at most six folders are listed")
local unreadable = Overview.unreadable(other.model)
t.assertEqual(#unreadable.paths, 6, "six folders are listed")
t.assertEqual(unreadable.paths[1], "~/Library/Protected 1", "folders are shown from the home folder")
t.assertEqual(unreadable.total, 8, "a folder reported twice counts once")
other.model.scan.issues = {}
other:show("overview", true)
t.expect(other.pages.overview.notMeasured.refs.unmeasured_privacy == nil, "no access request when everything was readable")

-- The App Store build runs in the App Sandbox, which hides the startup disk
-- until the person chooses it, whatever Full Disk Access says. The sheet
-- asks for the disk first, on every launch until it is chosen.
local sandboxed = Mock.new()
local diskChosen, fullAccess, pickerAnswers = false, false, {}
sandboxed.hasDiskAccess = function() return diskChosen end
sandboxed.hasFullDiskAccess = function() return fullAccess end
sandboxed.requestDiskAccess = function() diskChosen = table.remove(pickerAnswers, 1) == true; return diskChosen end
sandboxed.openSettings = function() end
sandboxed.saveFlag("onboarded", true)
local boxed = Controller.new(sandboxed)
boxed:createWindow()
local steps = boxed.onboarding
t.expect(steps.sheet ~= nil, "a missing disk shows the sheet even after onboarding was seen")
t.assertEqual(steps:stage(), "disk", "the disk comes before Full Disk Access")
t.expect(steps.refs.chooseDisk ~= nil and steps.refs.openSettings == nil, "the disk stage offers Choose Disk, not Settings")
fullAccess = true
t.expect(not steps:poll(), "Full Disk Access alone does not continue while the disk is hidden")
fullAccess = false
table.insert(pickerAnswers, false)
t.expect(not steps:chooseDisk() and steps.sheet ~= nil and steps:stage() == "disk", "cancelling the panel keeps the disk stage")
sandboxed.saveFlag("onboarded", false)
table.insert(pickerAnswers, true)
t.expect(steps:chooseDisk(), "choosing the disk is accepted")
t.assertEqual(steps:stage(), "fullDisk", "then the sheet asks for Full Disk Access")
t.expect(steps.sheet ~= nil and steps.refs.openSettings ~= nil and steps.refs.chooseDisk == nil, "the same flow shows the Full Disk Access stage")
t.expect(boxed.model.scan.completedAt == nil, "the scan still waits")
fullAccess = true
t.expect(steps:poll() and steps.sheet == nil, "granting Full Disk Access then continues")
t.expect(boxed.model.scan.completedAt ~= nil, "and the scan starts")

-- Choosing the disk when Full Disk Access is already on closes the sheet.
local ready = Mock.new()
local readyDisk = false
ready.hasDiskAccess = function() return readyDisk end
ready.hasFullDiskAccess = function() return true end
ready.requestDiskAccess = function() readyDisk = true; return true end
local quick = Controller.new(ready)
quick:createWindow()
t.expect(quick.onboarding:chooseDisk() and quick.onboarding.sheet == nil and quick.model.scan.completedAt ~= nil, "with Full Disk Access on, the disk is the only step")

-- Skipped: the Overview names the folders and offers the disk, not Settings,
-- as Full Disk Access cannot help while the sandbox refuses first.
local hidden = Mock.new()
local hiddenDisk, requested, settingsOpened = false, 0, 0
hidden.hasDiskAccess = function() return hiddenDisk end
hidden.hasFullDiskAccess = function() return false end
hidden.requestDiskAccess = function() requested = requested + 1; hiddenDisk = true; return true end
hidden.openSettings = function() settingsOpened = settingsOpened + 1 end
local skipped = Controller.new(hidden)
skipped:createWindow()
skipped.onboarding:finish(false)
t.assertEqual(skipped:state().diskAccess, false, "the hidden disk is known after the scan")
local hiddenHome = hidden.home
skipped.model.scan.issues = {{path = hiddenHome .. "/Library/Mail", reason = "Operation not permitted"}}
local diskCard = Overview.unmeasured(skipped.model, skipped:state().disk, {fullDiskAccess = false, diskAccess = false})
local diskItem
for _, item in ipairs(diskCard.items) do if item.id == "privacy" then diskItem = item end end
t.assertEqual(diskItem.title, "Needs access to your disk", "the card names the disk as what is missing")
t.assertEqual(diskItem.grantTitle, "Allow Access to Disk…", "and offers the disk")
skipped:show("overview", true)
t.assertEqual(skipped.pages.overview.notMeasured.refs.grantAccess.title, "Allow Access to Disk…", "the button says so")
local rescans, start = 0, skipped.scan.start
skipped.scan.start = function(scan) rescans = rescans + 1; return start(scan) end
t.expect(skipped:grantAccess(), "the button asks for the disk")
t.expect(requested == 1 and settingsOpened == 0, "it opens the panel, not Settings")
t.expect(skipped.diskAccess == true and rescans == 1, "and measures again with the disk")
t.expect(skipped:grantAccess() and settingsOpened == 1, "with the disk, the button opens Full Disk Access")
skipped.model.scan.issues = {{path = hiddenHome .. "/Library/Mail", reason = "Operation not permitted"}}
local fdaCard = Overview.unmeasured(skipped.model, skipped:state().disk, {fullDiskAccess = false, diskAccess = true})
diskItem = nil
for _, item in ipairs(fdaCard.items) do if item.id == "privacy" then diskItem = item end end
t.assertEqual(diskItem.title, "Needs Full Disk Access", "with the disk, Full Disk Access is what is missing")

-- The synthetic disk cannot tell, so it never shows onboarding.
t.expect(not Controller.new(Mock.new()).onboarding, "the onboarding controller exists only once a window opens")
local plain = Controller.new(Mock.new())
plain:createWindow()
t.expect(plain.onboarding.sheet == nil and plain.model.scan.completedAt ~= nil, "without an access probe, the scan starts directly")

os.exit(t.summary() and 0 or 1)
