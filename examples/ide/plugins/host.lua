local Registry = require("examples.ide.plugins.registry")

local Host = {}
Host.__index = Host

function Host.new(props)
	props = props or {}
	return setmetatable({
		loaded = {},
		native = {},
	}, Host)
end

function Host:loadLua(path)
	local module = Registry.loadLua(path)
	self.loaded[#self.loaded + 1] = path
	return module
end

function Host:loadModule(moduleName)
	local module = require(moduleName)
	self.loaded[#self.loaded + 1] = moduleName
	return module
end

function Host:loadNative(path, moduleName)
	local module = Registry.loadNative(path, moduleName)
	self.native[moduleName or path] = module
	return module
end

function Host:loadBuiltins()
	self:loadModule("examples.ide.plugins.text_editor")
	self:loadModule("examples.ide.plugins.image_viewer")
	self:loadModule("examples.ide.plugins.native_controls")
	return self
end

function Host:get(id)
	return Registry.get(id)
end

function Host:resolveFile(path, kind)
	return Registry.resolveByFile(path, kind or "editor")
end

function Host:openFile(path, props)
	local spec = self:resolveFile(path)
	if not spec then
		return nil
	end
	props = props or {}
	props.path = props.path or path
	return spec.create(props)
end

return Host
