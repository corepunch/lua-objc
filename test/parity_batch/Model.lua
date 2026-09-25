local Model = {}
Model.__index = Model

-- `batch` is the injected native runner (services/Batch.lua).
function Model.new(batch)
	return setmetatable({ batch = assert(batch, "batch runner is required"), count = 0 }, Model)
end

function Model:run(inputPath, outputPath)
	self.count, self.runId = self.batch.run(inputPath, outputPath)
	return self.count
end

function Model:presentation()
	return { count = self.count, runId = self.runId or "" }
end

return Model
