local App = require("App")
local native = App.loadNativePlugin(assert(package.searchpath("StorageScan", package.cpath)), "StorageScan")
local Scanner = {}
function Scanner.start(paths, exclusions, options)
	return {handle = native.start(paths, exclusions or {}, options)}
end
function Scanner.startExport(paths, exclusions, outputPath, metadata)
	return {handle = native.exportStart(paths, exclusions or {}, outputPath, metadata)}
end
-- Decoded record chunks of a Mock HDD snapshot, then nil.
function Scanner.snapshotRecords(path)
	return native.snapshotRecords(path)
end
-- Writes a snapshot from `{path, allocatedBytes, countedBytes}` items in
-- path order; `metadata` holds capacityBytes, availableBytes and createdAt.
function Scanner.writeSnapshot(path, metadata, items)
	native.snapshotWrite(path, metadata, items)
end
function Scanner.cancel(job)
	if not job then return end
	job.cancelled = true
	if job.handle then native.cancel(job.handle); job.handle = nil end
end
-- Items met so far by a running scan, for progress while one large root
-- is still being walked.
function Scanner.progress(job)
	return job.handle and native.progress(job.handle) or nil
end
function Scanner.poll(job)
	if not job.handle then return true, {failure = "Measurement cancelled."} end
	local done, result = native.poll(job.handle)
	if done then job.handle = nil end
	if result and not done and result.completed == job.completed then return false end
	if result then job.completed = result.completed end
	return done, result
end
function Scanner.startDuplicates(roots, options) return {handle = native.duplicatesStart(roots, options)} end
function Scanner.pollDuplicates(job)
	if not job.handle then return true, {failure = "Search cancelled.", groups = {}} end
	return native.duplicatesPoll(job.handle)
end
function Scanner.cancelDuplicates(job)
	job.cancelled = true
	if job.handle then native.duplicatesCancel(job.handle); job.handle = nil end
end
Scanner.commandStart = native.commandStart
Scanner.commandPoll = native.commandPoll
return Scanner
