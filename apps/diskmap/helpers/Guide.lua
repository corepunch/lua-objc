local Format = require("apps.diskmap.helpers.Format")
local Guide = {}

Guide.chapters = require("apps.diskmap.knowledge.Guide")

local function searchable(topic)
	return table.concat({topic.title, topic.summary, topic.what, topic.why, topic.action or "",
		table.concat(topic.paths or {}, " ")}, " "):lower()
end

-- The live measurement for a topic's resources, summed across its catalog
-- rows. Unmeasured, excluded or system-managed rows add no bytes; if none of
-- them has bytes (or one is still being measured) the topic shows no size
-- rather than an invented zero or a partial sum. `lookup(id)` answers a
-- location's rolled-up row (Categories.measured).
function Guide.measurement(topic, lookup)
	local bytes, measured, partial = 0, false, false
	for _, id in ipairs(topic.resources or {}) do
		local row = lookup(id)
		if row then
			if row.bytes then bytes = bytes + row.bytes; measured = true end
			if row.status == "partial" then partial = true end
			if row.calculating then return nil end
		end
	end
	if not measured then return nil end
	return Format.atLeast(bytes, partial) .. " on this Mac"
end

-- The advice a topic shows: its own `action`, or the catalog advice of the
-- first of its resources that has one (`advice(id)`), so a topic about one
-- location never restates what the catalog entry already says.
function Guide.action(topic, advice)
	if topic.action then return topic.action end
	for _, id in ipairs(topic.resources or {}) do
		local text = advice and advice(id)
		if text then return text end
	end
end

-- Every chapter and its topics, in guide order. `measured(id)` answers a
-- location's rolled-up row, `advice(id)` its catalog advice.
function Guide.presentation(measured, advice)
	local chapters = {}
	for chapterIndex, chapter in ipairs(Guide.chapters) do
		local topics = {}
		for topicIndex, topic in ipairs(chapter.topics) do
			table.insert(topics, {id = topic.id, key = chapterIndex .. "_" .. topicIndex,
				title = topic.title, icon = topic.icon, summary = topic.summary,
				what = topic.what, why = topic.why, action = Guide.action(topic, advice),
				paths = table.concat(topic.paths or {}, "\n"), open = topic.open,
				measurement = Guide.measurement(topic, measured)})
		end
		table.insert(chapters, {id = chapter.id, title = chapter.title, icon = chapter.icon, topics = topics})
	end
	return {chapters = chapters}
end

-- The topics that mention `needle` (lowered), in guide order: those of a
-- chapter whose title matches, and any whose text does.
function Guide.search(needle)
	local found = {}
	for _, chapter in ipairs(Guide.chapters) do
		local chapterMatches = chapter.title:lower():find(needle, 1, true) ~= nil
		for _, topic in ipairs(chapter.topics) do
			if chapterMatches or searchable(topic):find(needle, 1, true) then
				table.insert(found, {id = topic.id, title = topic.title, icon = topic.icon, summary = topic.summary, chapter = chapter.title})
			end
		end
	end
	return found
end

function Guide.topic(id)
	for _, chapter in ipairs(Guide.chapters) do
		for _, topic in ipairs(chapter.topics) do if topic.id == id then return topic end end
	end
end

return Guide
