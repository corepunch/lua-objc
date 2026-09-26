-- Run against the real platform controls, both headlessly on AppKit and in
-- the UIKit batch host. These checks inspect rendered label geometry after
-- native layout, so an oversized symbol cannot pass on template properties.
local M = {}

function M.run(ns)
	local xml = require("ui.xml")
	local _, refs = xml.renderFile("apps/adventure-arena/views/Session.etlua", {
		transcript = "Opening scene", speechAvailable = true,
		actions = { disappear = function() end, readingSettings = function() end },
	}, ns)
	-- Session.etlua is a <Page>; measure its content view.
	local root = refs.session
	local count = 0
	local function expect(value, message)
		assert(value, message)
		count = count + 1
	end
	local function containsImage(button)
		local frame, bounds = button.imageView.frame, button.bounds
		expect(frame.size.width > 0 and frame.size.height > 0, "native button has visible symbol geometry")
		expect(frame.origin.x >= 0 and frame.origin.y >= 0, "symbol starts inside its button")
		expect(frame.origin.x + frame.size.width <= bounds.size.width,
			"symbol fits button width without clipping or overflow")
		expect(frame.origin.y + frame.size.height <= bounds.size.height,
			"symbol fits button height without clipping or overflow")
	end
	for _, width in ipairs({ 320, 402, 430, 320 }) do
		for _, hasText in ipairs({ false, true, false, true }) do
			refs.input.text = hasText and "look north" or ""
			refs.send.hidden, refs.dictate.hidden = not hasText, hasText
			refs.send.enabled = hasText
			local active = hasText and refs.send or refs.dictate
			local json = ns._parityMeasure(root, {
				{ id = "action", view = active }, { id = "field", view = refs.input },
			}, { schema = 1, runId = "composer-contract", id = "composer", width = width, height = 600 })
			local result = ns._jsonParse(json)
			local action, field = result.probes[1], result.probes[2]
			expect(action.width == 38 and action.height == 44, "composer preserves the SwiftUI action frame")
			expect(field.width > 0 and field.x + field.width <= action.x, "input and action do not overlap")
			expect(action.x + action.width <= width, "action remains within the screen after resize")
			if result.platform == "ios" then
				containsImage(active)
				containsImage(refs.quickActions)
				local glass = active.superview.superview.superview
				expect(glass.effect ~= nil and not glass.clipsToBounds,
					"native glass shapes the material without clipping its content")
			end
		end
	end
	return count
end

return M
