local DataModel = require("data.model")

-- A page of chapters of topics to read: the Storage Guide and Diskmap Help,
-- two ids of one class, each built from the model named by its manifest
-- entry's `source` (models/Guide.lua, models/Help.lua), whose `page(services)` is
--
--   topic          the template in views/ that draws one topic
--   summary        the header's second line
--   noun           "No <noun> mentions …", when a search finds nothing
--   present(query) -> {chapters, empty}
--   follow(topic)  what the topic's button does, or nil for no button
local TopicsPage = DataModel.define({})

function TopicsPage.new(_, services, id)
	return setmetatable({services = services, page = require("apps.diskmap.models." .. services.entry(id).attrs.source).page(services)}, TopicsPage)
end

-- The answer is asked again only when the search changes or a scan starts or
-- ends: scan progress would otherwise rebuild every topic and collapse the
-- one being read, and the sizes it measures are shown once it is done.
function TopicsPage:data(state)
	local page, query = self.page, state.query or ""
	local key = query .. tostring(self.services.model.scan.running == true)
	if not self.answer or self.key ~= key then self.key, self.answer = key, page.present(state.query) end
	local handlers = {}
	for _, chapter in ipairs(self.answer.chapters) do
		for _, topic in ipairs(chapter.topics) do handlers["open_" .. topic.id] = page.follow(topic) end
	end
	return {chapters = self.answer.chapters, empty = self.answer.empty, summary = page.summary, topic = page.topic,
		noun = page.noun, query = query, expandAll = query ~= "", handlers = handlers}
end

function TopicsPage:deactivate() self.answer = nil end

return TopicsPage
