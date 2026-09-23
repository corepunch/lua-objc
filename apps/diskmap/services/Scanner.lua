local App = require("App")
local native = App.loadNativePlugin(assert(package.searchpath("StorageScan", package.cpath)), "StorageScan")
local Scanner = {}
function Scanner.start(paths, exclusions)
	return {handle = native.start(paths, exclusions or {})}
end
function Scanner.startExport(paths, exclusions, outputPath, metadata)
	return {handle = native.exportStart(paths, exclusions or {}, outputPath, metadata)}
end
function Scanner.cancel(job)
	if not job then return end
	job.cancelled = true
	if job.handle then native.cancel(job.handle); job.handle = nil end
end
function Scanner.poll(job)
	if not job.handle then return true, {failure = "Measurement cancelled."} end
	local done, result = native.poll(job.handle)
	if done then job.handle = nil end
	if result and not done and result.completed == job.completed then return false end
	if result then job.completed = result.completed end
	return done, result
end
Scanner.commandStart = native.commandStart
Scanner.commandPoll = native.commandPoll
return Scanner
