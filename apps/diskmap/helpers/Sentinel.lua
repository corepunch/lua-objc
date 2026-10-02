local Format = require("apps.diskmap.helpers.Format")
local Sentinel = {}

-- Opt-in, while Diskmap is open: when an app lands in the Trash, offer to
-- mark the data it left in the Library, as Pearcleaner's Sentinel does.
-- Nothing is marked until the person clicks the notification's action.
Sentinel.minimumBytes = 50e6

-- Apps that arrived in the Trash, from a batch of file system events.
function Sentinel.trashedApps(events, trash)
	local apps, seen = {}, {}
	for _, event in ipairs(events or {}) do
		local path = event.path or ""
		local app = path:match("^(" .. trash:gsub("%p", "%%%0") .. "/[^/]+%.app)")
		if app and (event.created or event.renamed) and not event.removed and not seen[app] then
			seen[app] = true
			table.insert(apps, app)
		end
	end
	return apps
end

-- The name an app's data is filed under: its bundle's name.
function Sentinel.name(appPath) return (appPath:match("([^/]+)%.app$") or appPath) end

-- The offer for the data a trashed app left behind (`folders` and their
-- `bytes`, from Applications:data), or nil when it is too small to mention.
function Sentinel.offer(appPath, bundleId, folders, bytes)
	local name = Sentinel.name(appPath)
	if bytes < Sentinel.minimumBytes then return nil end
	return {name = name, bundleId = bundleId, folders = folders, bytes = bytes,
		notification = {id = "diskmap.sentinel." .. (bundleId or name), title = name .. " is in the Trash",
			body = "It left " .. Format.size(bytes) .. " of data in your Library. Review it in Diskmap before you empty the Trash.",
			action = "Mark for Cleanup"}}
end

return Sentinel
