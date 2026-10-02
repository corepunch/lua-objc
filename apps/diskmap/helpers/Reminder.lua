local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local History = require("apps.diskmap.helpers.History")
local Reminder = {}

-- The opt-in monthly reminder: a notification on the first of each month
-- saying what grew over the last month. It is rescheduled after every scan,
-- so it always describes the newest recorded history.
Reminder.id = "diskmap.monthly"
Reminder.day, Reminder.hour = 1, 10
Reminder.days = 30
-- Growth smaller than this is not worth a notification line.
Reminder.minimumGrowth = 1e9

-- The notification for recorded history, or nil when too little is known.
function Reminder.notification(entries, now)
	local model = Model.db
	local changes = History:changes(entries, Reminder.days, 3, now)
	local grew = {}
	for _, row in ipairs(changes and changes.rows or {}) do
		if row.delta >= Reminder.minimumGrowth then table.insert(grew, row.name .. " grew by " .. Format.size(row.delta)) end
	end
	local body
	if #grew == 0 then
		if not changes then return nil end
		body = "Nothing grew by more than " .. Format.size(Reminder.minimumGrowth) .. " since " .. changes.since .. "."
	else
		body = table.concat(grew, "; ") .. " since " .. changes.since .. "."
	end
	return {id = Reminder.id, title = "Your storage this month", body = body, action = "Open Diskmap",
		day = Reminder.day, hour = Reminder.hour, repeats = true}
end

return Reminder
