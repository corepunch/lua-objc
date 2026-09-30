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

-- The synthetic disk cannot tell, so it never shows onboarding.
t.expect(not Controller.new(Mock.new()).onboarding, "the onboarding controller exists only once a window opens")
local plain = Controller.new(Mock.new())
plain:createWindow()
t.expect(plain.onboarding.sheet == nil and plain.model.scan.completedAt ~= nil, "without an access probe, the scan starts directly")

os.exit(t.summary() and 0 or 1)
