local App = require("App")
-- The native StorageScan plugin (src/plugins/storage): bulk metadata
-- enumeration of a list of roots, and asynchronous commands such as simctl
-- and git. Only services/System.lua calls it.
local native = App.loadNativePlugin(assert(package.searchpath("StorageScan", package.cpath)), "StorageScan")
local Scanner = {}
function Scanner.start(paths, exclusions, options)
	return {handle = native.start(paths, exclusions or {}, options)}
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
	-- One live update per second even when the worker is still inside a large
	-- location. Completed roots still publish immediately.
	local seconds = result and math.floor(result.seconds or 0)
	if result and not done and result.completed == job.completed and seconds == job.seconds then return false end
	if result then job.completed, job.seconds = result.completed, seconds end
	return done, result
end
Scanner.commandStart = native.commandStart
Scanner.commandPoll = native.commandPoll
return Scanner
