-- Native side of the streamed parity batch: runs the platform contracts,
-- reads the input matrix from the device Documents directory, and measures
-- every case with real views.
local ns = require("ns")
local batch = require("parity.batch")
local Batch = {}

function Batch.run(inputPath, outputPath)
	require("parity.contracts").run(ns)
	require("parity.composer_contracts").run(ns)
	local documents = ns._parityDocumentsDirectory()
	inputPath = inputPath or os.getenv("PARITY_BATCH_INPUT") or documents .. "/parity-input.json"
	outputPath = outputPath or os.getenv("PARITY_BATCH_OUTPUT") or documents .. "/parity-results"
	local input = ns._parityReadJSON(inputPath)
	return batch.run(input, outputPath), input.runId
end

return Batch
