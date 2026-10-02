local Format = require("apps.diskmap.helpers.Format")
local Guide = {}

Guide.chapters = require("apps.diskmap.knowledge.Guide")

local function searchable(topic)
	return table.concat({topic.title, topic.summary, topic.what, topic.why, topic.action,
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

-- Chapters and topics matching `query`, in guide order. A chapter whose title
-- matches keeps all of its topics; otherwise only matching topics remain.
function Guide.presentation(query, measured)
	local needle = (query or ""):lower()
	local chapters, count = {}, 0
	for chapterIndex, chapter in ipairs(Guide.chapters) do
		local chapterMatches = needle == "" or chapter.title:lower():find(needle, 1, true) ~= nil
		local topics = {}
		for topicIndex, topic in ipairs(chapter.topics) do
			if chapterMatches or searchable(topic):find(needle, 1, true) then
				table.insert(topics, {id = topic.id, key = chapterIndex .. "_" .. topicIndex,
					title = topic.title, icon = topic.icon, summary = topic.summary,
					what = topic.what, why = topic.why, action = topic.action,
					paths = table.concat(topic.paths or {}, "\n"), open = topic.open,
					measurement = Guide.measurement(topic, measured)})
			end
		end
		if #topics > 0 then
			count = count + #topics
			table.insert(chapters, {id = chapter.id, title = chapter.title, icon = chapter.icon, topics = topics})
		end
	end
	return {chapters = chapters, count = count, empty = count == 0}
end

function Guide.topic(id)
	for _, chapter in ipairs(Guide.chapters) do
		for _, topic in ipairs(chapter.topics) do if topic.id == id then return topic end end
	end
end

return Guide
