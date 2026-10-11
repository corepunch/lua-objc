-- The complete Diskmap runtime contract. Providers (services/System.lua on
-- a real Mac, services/Fixture.lua for tests and --showcase) expose every
-- member; callbacks complete even when the provider has no data, and
-- destructive members refuse rather than report a success that never
-- happened. Pages never discover capabilities by missing functions.
local Contract = {}
Contract.members = {
	children = "(path) -> {{name, path, directory}}",
	cleanupProbes = "() -> {running, appPath, identity, exists}",
	command = "(argv, completion) -> completion(ok, output)",
	confirmAction = "(title, message, parent?) -> boolean",
	copy = "(text)",
	decode = "(json)",
	diskSpace = "(path) -> {freeKb, totalKb}",
	exists = "(path)",
	fileIdentity = "(path) -> {inode, device, symlink}",
	hasFullDiskAccess = "()",
	installedApplications = "(completion) -> completion(apps {path, bundleId, name, team?, groups?})",
	loadFolders = "(name)",
	loadKeep = "()",
	logOperation = "(line)",
	measure = "(paths, exclusions, completion) -> job; completion(records {bytes, used, state, children})",
	cancel = "(job)",
	onOpenFiles = "(handler)",
	openSettings = "(section)",
	operationLog = "()",
	pickFolder = "(title)",
	quickLook = "(paths, index)",
	readPropertyList = "(path)",
	reveal = "(path)",
	saveFolders = "(name, roots)",
	saveKeep = "(kept)",
	scanFolder = "(path, options, completion, progress) -> job; completion(tree?, failure?, stats)",
	cancelFolderScan = "(job)",
	showError = "(title, message, parent?)",
	simulatorDevices = "(completion) -> completion(listed?, error?)",
	simulatorRuntimes = "(completion) -> completion(runtimes?, error?)",
	tmpdir = "() -> path",
	trash = "(path) -> ok, message",
	volumeCapacity = "(path) -> {total, available}",
	volumes = "(completion) -> completion({name, role, bytes})",
	worktreeScan = "(roots, completion, progress) -> completion(entries, facts)",
	worktreeState = "(row, completion) -> completion(entry?, facts?)",
}

function Contract.check(service)
	assert(type(service) == "table", "Diskmap service must be a table")
	for name, signature in pairs(Contract.members) do
		assert(type(service[name]) == "function", "Diskmap service requires " .. name .. signature)
	end
	return service
end

-- A recording test may replace any member. Missing IO does nothing;
-- destructive work refuses instead of reporting a success that never happened.
function Contract.stub(overrides)
	local service = {home = "/Users/test", mock = false, badge = false, label = false}
	local function none() end
	for name in pairs(Contract.members) do service[name] = none end
	for _, name in ipairs({"children", "loadKeep", "loadFolders", "cleanupProbes", "operationLog"}) do service[name] = function() return {} end end
	for _, name in ipairs({"exists", "hasFullDiskAccess", "confirmAction"}) do service[name] = function() return false end end
	for _, name in ipairs({"saveKeep", "saveFolders", "logOperation"}) do service[name] = function() return true end end
	service.trash = function() return false, "Unavailable in this test" end
	service.tmpdir = function() return "/private/var/folders/zz/test/T" end
	service.measure = function(paths, _, done)
		local records = {}
		for index in ipairs(paths) do records[index] = {bytes = 0, state = "missing"} end
		done(records)
		return {}
	end
	service.simulatorDevices = function(done) done(nil, "Unavailable in this test") end
	service.simulatorRuntimes = function(done) done(nil, "Unavailable in this test") end
	service.installedApplications = function(done) done(nil) end
	service.volumes = function(done) done({}) end
	service.worktreeScan = function(_, done) done({}, {}) end
	service.worktreeState = function(_, done) done(nil, nil) end
	service.scanFolder = function(_, _, done) done(nil, "Unavailable in this test", {}) end
	service.command = function(_, done) done(false, "Unavailable in this test") end
	service.decode = function(value) return require("AppKit").json_parse(value) end
	for name, value in pairs(overrides or {}) do service[name] = value end
	return Contract.check(service)
end

return Contract
