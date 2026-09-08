-- macOS: PARITY_BATCH_INPUT=/path/input.json PARITY_BATCH_OUTPUT=/path/output
-- ./lua-objc --test scripts/parity/batch_candidate.lua
-- In an existing streamed UIKit host, call require("parity.batch").run(input,
-- outputDirectory) on its main Lua state. This script never exits that host.
-- Exact streamed-controller invocation (output stays in the app container):
-- local ns = require("ns")
-- local input = assert(ns._jsonParse(assert(ns._readFile("path/input.json"))))
-- require("parity.batch").run(input, os.getenv("HOME") .. "/Documents/parity")
local batch = require("parity.batch")
batch.runEnvironment()
