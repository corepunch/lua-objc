--[[
  ui/transition.lua — Matched zoom navigation metadata (issue #21).

  Stores source/destination ids and namespace on views without driving
  frames from Lua. Reduce Motion disables zoom so the stack uses a
  plain push instead of a matched zoom.
]]

local Transition = {}

local sources = setmetatable({}, { __mode = "k" })
local destinations = setmetatable({}, { __mode = "k" })
local reduceMotionOverride

function Transition.setReduceMotion(value)
	if value == nil then reduceMotionOverride = nil
	else reduceMotionOverride = value and true or false end
end

function Transition.reduceMotion()
	if reduceMotionOverride ~= nil then return reduceMotionOverride end
	local ok, haptics = pcall(require, "ui.haptics")
	return ok and haptics.isReduceMotionEnabled() or false
end

function Transition.shouldZoom()
	return not Transition.reduceMotion()
end

local Namespace = {}
Namespace.__index = Namespace

function Namespace.new(name)
	return setmetatable({
		name = name or "default",
		ids = {},
	}, Namespace)
end

function Namespace:registerSource(id, view)
	assert(id ~= nil and id ~= "", "matched transition source requires an id")
	self.ids[id] = {
		kind = "source",
		view = view,
	}
	if view ~= nil then
		sources[view] = { id = id, namespace = self }
	end
	return view
end

function Namespace:registerDestination(id, view, opts)
	assert(id ~= nil and id ~= "", "zoom destination requires a source id")
	opts = opts or {}
	self.ids[id] = self.ids[id] or {}
	self.ids[id].destination = view
	self.ids[id].transition = opts.transition or "zoom"
	if view ~= nil then
		destinations[view] = {
			id = id,
			namespace = self,
			transition = opts.transition or "zoom",
			toolbarVisibility = opts.toolbarVisibility,
			ignoresSafeArea = opts.ignoresSafeArea,
		}
	end
	return view
end

function Namespace:source(id)
	local entry = self.ids[id]
	return entry and entry.view or nil
end

function Namespace:destination(id)
	local entry = self.ids[id]
	return entry and entry.destination or nil
end

function Namespace:hasPair(id)
	local entry = self.ids[id]
	return entry ~= nil and entry.view ~= nil and entry.destination ~= nil
end

function Transition.sourceOf(view)
	return sources[view]
end

function Transition.destinationOf(view)
	return destinations[view]
end

function Transition.applySource(view, props, namespaces)
	if not props or not props.matchedTransitionSourceId then
		return view
	end
	local ns = props.namespace
	if type(ns) == "string" and namespaces then
		ns = namespaces[ns]
	end
	if ns == nil then
		ns = Namespace.new(type(props.namespace) == "string" and props.namespace or "default")
		if type(props.namespace) == "string" and namespaces then
			namespaces[props.namespace] = ns
		end
	end
	ns:registerSource(props.matchedTransitionSourceId, view)
	return view
end

function Transition.applyDestination(view, props, namespaces)
	if not props then return view end
	local transition = props.navigationTransition
	local sourceId = props.sourceId or props.matchedTransitionSourceId
	if transition == nil and sourceId == nil then
		return view
	end
	local ns = props.namespace
	if type(ns) == "string" and namespaces then
		ns = namespaces[ns]
	end
	if ns == nil then
		ns = Namespace.new(type(props.namespace) == "string" and props.namespace or "default")
		if type(props.namespace) == "string" and namespaces then
			namespaces[props.namespace] = ns
		end
	end
	ns:registerDestination(sourceId or "cover", view, {
		transition = transition or "zoom",
		toolbarVisibility = props.toolbarVisibility,
		ignoresSafeArea = props.ignoresSafeArea,
	})
	return view
end

function Transition.pushOptions(sourceId, namespace)
	if not Transition.shouldZoom() then
		return { animated = true, transition = "push" }
	end
	return {
		animated = true,
		transition = "zoom",
		sourceId = sourceId,
		namespace = namespace and namespace.name or namespace,
	}
end

Transition.Namespace = Namespace
return Transition
