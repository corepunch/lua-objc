local ns = require("ns")
local batch = require("parity.batch")
local Model = {}
Model.__index = Model

function Model.new()
	return setmetatable({ count = 0 }, Model)
end

function Model:run(inputPath, outputPath)
	require("parity.contracts").run(ns)
	local documents = ns._parityDocumentsDirectory()
	inputPath = inputPath or os.getenv("PARITY_BATCH_INPUT") or documents .. "/parity-input.json"
	outputPath = outputPath or os.getenv("PARITY_BATCH_OUTPUT") or documents .. "/parity-results"
	local input = ns._parityReadJSON(inputPath)
	self.count = batch.run(input, outputPath)
	self.runId = input.runId
	return self.count
end

return Model
