local App = require("App")

local NativeControls = {}

function NativeControls.load(path)
	return App.loadNativePlugin(path, "ide_controls")
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

local registered = App.getPlugin(NativeControls.id)
if not registered then
	registered = App.registerPlugin(NativeControls)
end

return registered
