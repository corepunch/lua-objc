local ns = require("ns")

return function(model)
	return ns.VStack {
		ns.Text("Measured " .. model.count .. " cases"),
		ns.Text(model.runId),
	}
end
