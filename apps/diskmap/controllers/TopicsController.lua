local Page = require("apps.diskmap.controllers.PageController")
local Controller = Page.extend(nil, "Topics")

-- A page of chapters of topics to read: the Storage Guide and Diskmap Help.
-- `page` is a table:
--
--   id            the sidebar destination
--   summary       the header's second line
--   topic         the template in views/ that draws one topic
--   noun          "No <noun> mentions …", when a search finds nothing
--   present(query) → {chapters, empty}
--   follow(topic)  what the topic's button does, or nil for no button
function Controller.new(context, entry)
	local page = require("apps.diskmap.models." .. entry.attrs.source).page(context, entry)
	return setmetatable({page = page, id = page.id}, Controller)
end

function Controller:mount(host, state)
	self:attach(host)
	self.query = nil
	self:update(state)
	return self.refs
end

-- The page re-renders only when its search changes. Scan progress would
-- otherwise rebuild every topic and collapse the one being read; sizes
-- refresh the next time the page opens.
function Controller:update(state)
	if not self.template or (self.refs and self.query == state.query) then return end
	self.query = state.query
	local page = self.page
	local data = page.present(state.query)
	data.summary, data.topic, data.noun = page.summary, page.topic, page.noun
	data.query = state.query or ""
	data.expandAll = data.query ~= ""
	data.actions = {}
	for _, chapter in ipairs(data.chapters) do
		for _, topic in ipairs(chapter.topics) do
			data.actions["open_" .. topic.id] = page.follow(topic)
		end
	end
	self:render(data)
end

return Controller
