--[[
  ui/notifications.lua — local notifications (UNUserNotificationCenter).

  Installed as `ns.notifications` on both platforms:

    available()                 whether this process can post (it needs an
                                app bundle; the development runtime has none)
    requestAuthorization(fn)    asks once; fn(granted, message)
    post(options, onResponse)   posts or schedules a notification:
                                {id, title, subtitle, body, action, delay,
                                day, hour, minute, repeats}; onResponse(id,
                                action) runs when it is clicked ("open") or its
                                button is ("action"). Returns false when
                                notifications are unavailable.
    remove(id)                  withdraws a pending or delivered notification
]]

local M = {}

function M.install(ns, bridge)
	ns.notifications = {
		available = function() return bridge._notificationsAvailable() end,
		requestAuthorization = function(callback)
			bridge._requestNotifications(callback or function() end)
		end,
		post = function(options, onResponse)
			assert(type(options) == "table" and options.id, "a notification requires an id")
			return bridge._notify(options, onResponse)
		end,
		remove = function(id) bridge._removeNotification(id) end,
	}
end

return M
