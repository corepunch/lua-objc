local Registry = require("examples.ide.plugins.registry")

local NativeControls = {}

function NativeControls.load(path)
	return Registry.loadNative(path, "ide_controls")
end

NativeControls.id = "nativeControls"
NativeControls.kind = "provider"
NativeControls.title = "Native Controls"
NativeControls.summary = "Optional Objective-C controls loaded from a dynamic library."
NativeControls.capabilities = { "nativeControls" }
NativeControls.activation = {}
NativeControls.create = function(props)
	if not props or not props.module then
		error("NativeControls requires props.module")
	end
	return props.module[props.control or "ColorWell"](props)
end

local registered = Registry.get(NativeControls.id)
if not registered then
	registered = Registry.register(NativeControls)
end

return registered
