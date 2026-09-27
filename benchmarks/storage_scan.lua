-- Measures the StorageScan plugin on one folder: files per second, directory
-- metadata calls and elapsed time, for comparison with `du -skx` and with
-- BlitzTree's published method (docs/research/STORAGE_SCAN_BENCHMARK.md).
--
--   ./lua-objc benchmarks/storage_scan.lua [folder]
_G.__headless = true
local App = require("App")
local native = App.loadNativePlugin(assert(package.searchpath("StorageScan", package.cpath)), "StorageScan")
local root = App.args()[1] or os.getenv("HOME")
local started = os.clock()
local snapshot = native.scan({root}, {})
local tree = snapshot.trees[1]
print(string.format("root=%s\nfiles+dirs=%d\nbulkCalls=%d\nseconds=%.2f\nperSecond=%.0f\nGB=%.2f\nerrors=%d\ncpu=%.2f",
	root, snapshot.visited, snapshot.bulkCalls, snapshot.seconds, snapshot.visited / math.max(snapshot.seconds, 1e-6),
	type(tree) == "table" and tree.kb * 1024 / 1e9 or 0, snapshot.errors, os.clock() - started))
os.exit(0)
