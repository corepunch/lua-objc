_G.__headless = true
local t = require("TestKit")
local Model = require("apps.diskmap.Model")
local History = require("apps.diskmap.models.History")
local Reminder = require("apps.diskmap.models.Reminder")
local Sentinel = require("apps.diskmap.models.Sentinel")
local Notifications = require("apps.diskmap.services.Notifications")

-- The monthly reminder describes what grew.
local model = Model.new("/Users/test")
local day = 86400
local entries = {
	{time = 100 * day, totals = {developer = 10e9, documents = 5e9}},
	{time = 125 * day, totals = {developer = 24e9, documents = 5.2e9}},
}
local reminder = Reminder.notification(model, entries, 125 * day)
t.expect(reminder and reminder.body:find("Developer grew by 14.0 GB", 1, true), "the reminder names the category that grew")
t.expect(not reminder.body:find("Documents", 1, true), "small growth is left out")
t.expect(reminder.day == 1 and reminder.repeats and reminder.id == Reminder.id, "it repeats on the first of each month")
t.assertEqual(Reminder.notification(model, {entries[1]}), nil, "one scan is not enough history")
local flat = Reminder.notification(model, {entries[1], {time = 120 * day, totals = {developer = 10.1e9}}}, 120 * day)
t.expect(flat and flat.body:find("Nothing grew", 1, true), "a quiet month says so")

-- Sentinel recognises apps arriving in the Trash and what they left.
local trash = "/Users/test/.Trash"
local apps = Sentinel.trashedApps({
	{path = trash .. "/Old Editor.app", created = true, directory = true},
	{path = trash .. "/Old Editor.app/Contents/Info.plist", created = true},
	{path = trash .. "/notes.txt", created = true},
	{path = trash .. "/Gone.app", removed = true},
}, trash)
t.assertEqual(#apps, 1, "only apps arriving in the Trash count")
t.assertEqual(apps[1], trash .. "/Old Editor.app", "the app bundle is recognised")
model.breakdowns["app-containers"] = {{name = "com.old.editor", kb = 300 * 1024, directory = true}}
model.breakdowns["user-caches"] = {{name = "com.old.editor", kb = 40 * 1024, directory = true}}
local offer = Sentinel.offer(model, apps[1], "com.old.editor")
t.expect(offer and #offer.folders == 2 and offer.bytes > Sentinel.minimumBytes, "its data folders are found by bundle identifier")
t.expect(offer.notification.body:find("of data in your Library", 1, true), "the offer says how much it left")
t.assertEqual(Sentinel.offer(model, trash .. "/Tiny.app", "com.tiny.app"), nil, "apps that left little are not mentioned")

-- The controller follows the saved flags.
local posted, removed, flags, watchers, requested = {}, {}, {}, {}, 0
local service = {
	notificationsAvailable = function() return true end,
	loadFlag = function(name) return flags[name] == true end,
	saveFlag = function(name, value) flags[name] = value; return true end,
	requestNotifications = function(callback) requested = requested + 1; callback(true) end,
	notify = function(options, respond) posted[options.id] = {options = options, respond = respond}; return true end,
	removeNotification = function(id) table.insert(removed, id) end,
	watch = function(paths, callback)
		local watcher = {paths = paths, callback = callback, active = true}
		function watcher.cancel() watcher.active = false end
		table.insert(watchers, watcher)
		return watcher
	end,
	readPropertyList = function() return {CFBundleIdentifier = "com.old.editor"} end,
}
local marked, reviewed, shown = nil, 0, 0
local notifications = Notifications.new(model, service, {
	mark = function(items) marked = items end,
	review = function() reviewed = reviewed + 1 end,
	show = function() shown = shown + 1 end,
})
notifications:apply()
t.assertEqual(#watchers, 0, "nothing is watched until Sentinel is turned on")
t.assertEqual(removed[1], Reminder.id, "a disabled reminder is withdrawn")
notifications:setEnabled("sentinel", true)
t.expect(requested == 1 and flags.sentinel and #watchers == 1 and watchers[1].paths[1] == trash, "turning Sentinel on asks permission and watches the Trash")
watchers[1].callback({{path = trash .. "/Old Editor.app", created = true, directory = true}})
local sentinelPost = posted["diskmap.sentinel.com.old.editor"]
t.expect(sentinelPost ~= nil, "trashing an app posts an offer")
sentinelPost.respond(sentinelPost.options.id, "action")
t.expect(marked and #marked == 2 and reviewed == 1 and shown == 1, "the offer's action marks the data and opens the review")
notifications:setEnabled("sentinel", false)
t.expect(not watchers[1].active, "turning Sentinel off stops watching")
notifications:historyRecorded(entries)
t.assertEqual(posted[Reminder.id], nil, "the reminder waits until it is turned on")
notifications:setEnabled("reminder", true)
notifications:historyRecorded(entries)
t.expect(posted[Reminder.id] ~= nil, "each scan reschedules the reminder")
service.notificationsAvailable = function() return false end
t.expect(not notifications:available(), "without a notification center both stay off")

-- Settings: the reminder turns storage history on.
local Controller = require("apps.diskmap.Controller")
local Mock = require("apps.diskmap.services.Mock")
local mock = Mock.new()
mock.showError = function() end
local app = Controller.new(mock)
app:createWindow()
app:openSettings()
t.expect(app.settings.refs.reminder ~= nil and app.settings.refs.sentinel ~= nil, "Settings offers both notifications")
t.expect(not app.settings.history, "history starts off")
app.settings.refs.reminder.state = 1
app.settings:toggleNotification("reminder")
t.expect(app.settings.history and mock.loadFlag("reminder"), "turning the reminder on turns history on")
app.settings:close()
os.exit(t.summary() and 0 or 1)
