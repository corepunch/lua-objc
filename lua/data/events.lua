-- Change events. A model that changed posts itself here; the first post of a
-- burst posts one event to the run loop (src/shared/events.m), which the
-- application receives through ordinary NSEvent routing like a click or a key.
-- The handler drains the burst: each changed model once, however many times it
-- changed, and the views bound to it are set again. Nothing polls, so an idle
-- app does no work at all.
--
--   Events.post(fn, key)   run `fn` in the next event; the same `key` posted
--                          again before then runs once
--   Events.flush()         run what is pending now (tests, and code that must
--                          see the views updated)
--   Events.immediate       when true, posts run at once: headless tests, where
--                          no run loop turns
local Events = {}

Events.immediate = rawget(_G, "__headless") == true

local pending, order, scheduled = {}, {}, false

local function native()
	local ok, bridge = pcall(require, "AppKitNative")
	if not ok then ok, bridge = pcall(require, "UIKitNative") end
	return ok and bridge or nil
end

function Events.flush()
	scheduled = false
	-- A handler may post more; those run in this same drain.
	while #order > 0 do
		local batch = order
		order, pending = {}, {}
		for _, entry in ipairs(batch) do entry() end
	end
end

function Events.post(fn, key)
	key = key or fn
	if Events.immediate then fn(); return end
	if pending[key] then return end
	pending[key] = true
	table.insert(order, fn)
	if scheduled then return end
	scheduled = true
	local bridge = native()
	if bridge and bridge._postEvent then bridge._postEvent(Events.flush) else Events.flush() end
end

return Events
