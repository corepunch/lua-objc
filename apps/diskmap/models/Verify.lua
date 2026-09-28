local Model = require("apps.diskmap.Model")
local Basket = require("apps.diskmap.models.Basket")
local Verify = {}

-- Checks a marked item again just before it moves to the Trash, as
-- Headroom's Cleaner does (#52): a mark can be hours old. An item is
-- skipped, with a reason, when
-- - the app that writes it is running (a cache Xcode or Chrome still uses),
-- - the file that proved what it is has gone (package.json deleted),
-- - a different item now sits at its path (its inode changed),
-- - the app a leftover belonged to is installed again, or
-- - it lies in a protected system location, whatever marked it.
-- `probes` are injected by the service: `running` (a set of bundle
-- identifiers), `appPath(bundleId)`, `exists(path)` and `identity(path)`.

-- Hard guard, independent of the catalog: nothing below these moves.
Verify.protected = {"/System/", "/bin/", "/sbin/", "/usr/bin/", "/usr/lib/", "/usr/libexec/", "/usr/sbin/",
	"/usr/share/", "/private/etc/", "/private/var/db/", "/Library/Apple/", "/Library/Frameworks/"}

-- The bundle identifier a Library location belongs to, from its folder
-- name: ~/Library/Caches/com.google.Chrome, Containers/<id>, and so on.
function Verify.bundleId(path)
	for _, folder in ipairs({"Caches", "Containers", "Group Containers", "Application Support", "HTTPStorages", "WebKit", "Logs"}) do
		local id = path:match("/Library/" .. folder:gsub("%s", "%%s") .. "/([%w%-]+%.[%w%.%-]+)")
		if id then return id end
	end
	return nil
end

-- The running app that blocks `bundleId`: the app itself, or the app a
-- helper belongs to (com.google.Chrome.helper is blocked by Chrome).
function Verify.blockingApp(bundleId, running)
	if not bundleId or not running then return nil end
	for id in pairs(running) do
		if id == bundleId or bundleId:sub(1, #id + 1) == id .. "." then return id end
	end
	return nil
end

-- An app's name for a skip reason: its bundle's name, or its identifier.
local function appName(bundleId, probes)
	local path = probes.appPath and probes.appPath(bundleId)
	return path and path:match("([^/]+)%.app/?$") or bundleId
end

-- Returns true, or false with {code, reason}. `item` is a basket item
-- {path, resourceId, bundleId, leftover, identity}; `resource` its catalog
-- row when it has one.
function Verify.check(item, resource, home, probes)
	probes = probes or {}
	local path = item.path
	for _, prefix in ipairs(Verify.protected) do
		if path:sub(1, #prefix) == prefix then return false, {code = "protected", reason = "it is in a protected system location"} end
	end
	local valid, why = Basket.validate(path, home)
	if not valid then return false, {code = "location", reason = why:gsub("%.$", ""):lower()} end
	if probes.exists and not probes.exists(path) then return false, {code = "missing", reason = "it is no longer there"} end
	if item.identity and probes.identity then
		local now = probes.identity(path)
		if not now or now.inode ~= item.identity.inode or now.device ~= item.identity.device then
			return false, {code = "replaced", reason = "a different item is at its place now"}
		end
		if now.symlink then return false, {code = "symlink", reason = "it is a symbolic link now"} end
	end
	local marker = resource and resource.marker
	if marker and probes.exists and not probes.exists(marker) then
		return false, {code = "marker", reason = "the project file that identified it is gone"}
	end
	local leftoverId = item.leftover and (item.bundleId or Verify.bundleId(path))
	if leftoverId and probes.appPath and probes.appPath(leftoverId) then
		return false, {code = "reinstalled", reason = "its app is installed again"}
	end
	local owner = item.bundleId or resource and resource.appIcon or Verify.bundleId(path)
	local blocking = Verify.blockingApp(owner, probes.running)
	if blocking then return false, {code = "running", reason = appName(blocking, probes) .. " was open"} end
	return true
end

-- The result of a cleanup, as the sheet reports it: what moved, grouped
-- skip reasons ("2 skipped because Xcode was open"), and free space before,
-- now and after emptying the Trash.
function Verify.summary(result)
	local lines = {}
	table.insert(lines, Model.size(result.movedBytes or 0) .. " moved to the Trash · " .. Model.plural(result.moved or 0, "item"))
	local order, counts = {}, {}
	for _, reason in ipairs(result.skipped or {}) do
		if not counts[reason] then counts[reason] = 0; table.insert(order, reason) end
		counts[reason] = counts[reason] + 1
	end
	for _, reason in ipairs(order) do
		table.insert(lines, counts[reason] .. " skipped because " .. reason)
	end
	if result.freeBefore and result.freeNow then
		table.insert(lines, "Free before: " .. Model.size(result.freeBefore) .. " · Free now: " .. Model.size(result.freeNow)
			.. " · After emptying the Trash, up to " .. Model.size(result.freeNow + (result.movedBytes or 0)))
	end
	return table.concat(lines, "\n")
end

return Verify
