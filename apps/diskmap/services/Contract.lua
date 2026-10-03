-- The complete Diskmap runtime contract. Providers expose all members;
-- unknown access is nil, empty inventories are {}, and callbacks complete
-- even when the provider has no data. Pages never discover capabilities by
-- missing functions. Stubs are explicit, safe, and never use the real disk.
local Contract = {}
Contract.members = {
	agentEntries = "(model)",
	analyzeFolder = "(path, completion) -> completion(entries, failure?, errors)",
	apfsVolumes = "(completion) -> completion(volumes, container?)",
	applicationInfo = "(paths, completion) -> completion(infoByPath)",
	await = "(job, completion, progress) -> completion(result)",
	bundles = "(root, kind)",
	cancel = "(job)",
	cancelFolderScan = "(job)",
	children = "(path)",
	cleanupProbes = "()",
	command = "(argv, completion) -> completion(ok, output)",
	confirmAction = "(title, message, parent?)",
	confirmEmptyTrash = "(row, size, parent?)",
	confirmOwnerCleanup = "(row, size, parent?)",
	confirmTrash = "(row, parent?)",
	confirmTrashPath = "(title, path, message, parent?)",
	copy = "(text)",
	decode = "(json)",
	discoverEntries = "(home, completion, projectRoots) -> completion(entries)",
	diskSpace = "(path)",
	emptyTrash = "()",
	exists = "(path)",
	exportMockSnapshot = "(outputPath, completion) -> completion(result {failure?})",
	fileIdentity = "(path)",
	findDuplicates = "(roots, completion, progress) -> completion(result)",
	findInstallers = "(home, completion) -> completion(records)",
	hasDiskAccess = "()",
	hasFullDiskAccess = "()",
	installedBundleIds = "(completion) -> completion(ids)",
	loadFlag = "(name)",
	loadFolders = "(name)",
	loadHistory = "()",
	loadHistorySetting = "()",
	loadKeep = "()",
	loadSettings = "()",
	loadSnapshotSummary = "()",
	loadWatchlist = "()",
	logOperation = "(line)",
	measure = "(paths, completion) -> completion(sizes, states)",
	monitor = "(visible, refresh)",
	moveItem = "(path, folder, completion) -> completion(ok, error?)",
	notificationsAvailable = "()",
	notify = "(options, onResponse)",
	onOpenFiles = "(handler)",
	openDiskUtility = "()",
	openOwner = "(owner)",
	openSettings = "(section)",
	operationLog = "()",
	pickFile = "(title)",
	pickFolder = "(title)",
	pickSaveFile = "(title, name)",
	poll = "(job)",
	projectInfo = "(path, completion) -> completion(info)",
	protectedLocations = "()",
	quickLook = "(paths, index)",
	readPropertyList = "(path)",
	relaunch = "(onFailure) -> completion(error (failure only))",
	removeNotification = "(id)",
	requestDiskAccess = "(parent?)",
	requestNotifications = "(callback) -> completion(granted)",
	reveal = "(path)",
	runOwnerCleanup = "(commandId, home, completion) -> completion(ok, output)",
	sandboxed = "()",
	saveFlag = "(name, enabled)",
	saveFolders = "(name, roots)",
	saveHistory = "(text)",
	saveHistorySetting = "(enabled)",
	saveKeep = "(kept)",
	saveSettings = "(enabled)",
	saveSnapshotSummary = "(text)",
	saveWatchlist = "(entries)",
	savedSnapshotPath = "()",
	scanFolder = "(path, options, completion, progress) -> completion(tree?, failure?, coverage)",
	showError = "(title, message, parent?)",
	simulatorDevices = "(completion) -> completion({devices})",
	simulatorRuntimes = "(completion) -> completion(runtimes?, error?)",
	simulatorState = "(udid, completion) -> completion(record?)",
	snapshotCount = "(completion) -> completion(count)",
	softwareUpdateStatus = "()",
	start = "(paths, exclusions, options)",
	trash = "(path)",
	volumeCapacity = "(path)",
	volumes = "(completion) -> completion(records)",
	watch = "(paths, callback)",
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
	local function empty() return {} end
	local function no() return false end
	for name in pairs(Contract.members) do service[name] = none end
	for _, name in ipairs({"children", "bundles", "agentEntries", "protectedLocations", "loadKeep", "loadWatchlist", "loadFolders", "cleanupProbes", "operationLog"}) do service[name] = empty end
	for _, name in ipairs({"loadSettings", "loadFlag", "loadHistorySetting", "exists", "sandboxed", "notificationsAvailable", "requestDiskAccess"}) do service[name] = no end
	for _, name in ipairs({"loadHistory", "loadSnapshotSummary"}) do service[name] = function() return "" end end
	for _, name in ipairs({"saveKeep", "saveWatchlist", "saveFolders", "saveSettings", "saveFlag", "saveHistorySetting", "saveHistory", "saveSnapshotSummary", "logOperation"}) do service[name] = function() return true end end
	for _, name in ipairs({"trash", "emptyTrash", "openOwner", "confirmTrash", "confirmTrashPath", "confirmEmptyTrash", "confirmOwnerCleanup", "confirmAction"}) do service[name] = no end
	service.start = function() return {} end
	service.await = function(_, done) done({trees = {}, rootStates = {}}) end
	service.poll = function() return true, {} end
	service.snapshotCount = function(done) done(nil) end
	service.measure = function(paths, done)
		local sizes, states = {}, {}
		for index in ipairs(paths) do sizes[index], states[index] = 0, "missing" end
		done(sizes, states)
	end
	service.discoverEntries = function(_, done) done({}) end
	service.simulatorDevices = function(done) done({devices = {}}) end
	service.simulatorRuntimes = function(done) done({}) end
	service.simulatorState = function(_, done) done(nil) end
	service.applicationInfo = function(_, done) done({}) end
	service.installedBundleIds = function(done) done({}) end
	service.apfsVolumes = function(done) done({}) end
	service.volumes = function(done) done({}) end
	service.worktreeScan = function(_, done) done({}, {}) end
	service.worktreeState = function(_, done) done({}) end
	service.projectInfo = function(_, done) done({loaded = true}) end
	service.findInstallers = function(_, done) done({}) end
	service.findDuplicates = function(_, done) done({groups = {}}) end
	service.analyzeFolder = function(_, done) done({}, "Unavailable in this test", 0) end
	service.scanFolder = function(_, _, done) done(nil, "Unavailable in this test", {}) end
	service.moveItem = function(_, _, done) done(false, "Unavailable in this test") end
	service.command = function(_, done) done(false, "Unavailable in this test") end
	service.runOwnerCleanup = function(_, _, done) done(false, "Unavailable in this test") end
	service.exportMockSnapshot = function(_, done) done({failure = "Unavailable in this test"}) end
	service.requestNotifications = function(done) done(false) end
	service.watch = function() return {cancel = none} end
	service.decode = function(value) return require("AppKit").json_parse(value) end
	for name, value in pairs(overrides or {}) do service[name] = value end
	return Contract.check(service)
end

return Contract
