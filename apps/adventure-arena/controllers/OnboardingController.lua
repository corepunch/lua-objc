local Onboarding = require("apps.adventure-arena.models.Onboarding")
local Template = require("ui.template")
local xml = require("ui.xml")

local Controller = {}
Controller.__index = Controller

local VIEW = "apps/adventure-arena/views/Onboarding.etlua"
local HOST = "apps/adventure-arena/views/OnboardingSheet.etlua"

function Controller.new(options)
	options = options or {}
	return setmetatable({
		model = options.model or Onboarding.new(options.store and options.store.load and options.store.load(),
			{ touch = options.ns ~= nil and options.ns.platform == "UIKit" }),
		store = options.store,
		adventures = assert(options.adventures, "catalog is required"),
		presentSheet = assert(options.presentSheet, "sheet presenter is required"),
		dismissSheet = assert(options.dismissSheet, "sheet dismisser is required"),
		openSession = options.openSession or function() return false end,
		ns = options.ns,
	}, Controller)
end

function Controller:needed()
	return self.model:needed()
end

function Controller:persist()
	if self.store and self.store.save then self.store.save(self.model:snapshot()) end
end

function Controller:presentation()
	local page = self.model:presentation(self.adventures)
	page.actions = {
		next = function() self:advance() end,
		back = function() self:retreat() end,
		skip = function() self:finish() end,
		done = function() self:finish() end,
		startStory = function() self:startRecommended() end,
		browse = function() self:finish() end,
	}
	for _, option in ipairs(page.audience) do
		local id = option.id
		page.actions["audience_" .. id] = function() self:chooseAudience(id) end
	end
	for index, world in ipairs(page.worlds) do
		local genre = world.title
		page.actions["world_" .. index] = function() self:chooseWorld(genre) end
	end
	return page
end

function Controller:render()
	if self.page then return self.page:update(self:presentation()) end
	return xml.renderFile(VIEW, self:presentation(), self.ns)
end

function Controller:refresh()
	if not self.page then return self:render() end
	local _, refs = self.page:update(self:presentation())
	self.refs = refs
	return self.page.view, refs
end

-- Large sheet so the tour reads as a first-launch screen, not a settings
-- panel. The page is a retained template; later steps update it in place.
function Controller:present(parent)
	local sheet, hostRefs = xml.renderFile(HOST, {}, self.ns)
	self.page = Template.new(hostRefs.page, VIEW, self.ns)
	local _, refs = self.page:update(self:presentation())
	self.sheet = self.presentSheet(sheet, { "large" })
	self.refs = refs
	self.parent = parent
	return self.sheet, refs
end

function Controller:open(parent)
	if not self:needed() then return nil end
	return self:present(parent)
end

-- "How to Play" in Settings: the guide pages again, for a reader who has
-- already been through the tour. One sheet at a time.
function Controller:openGuide(parent)
	if self.sheet then return nil end
	self.model:replay()
	return self:present(parent)
end

-- A page that scrolled opens the next one at its top.
function Controller:turn()
	self:refresh()
	if self.refs and self.refs.content then self.refs.content:scrollTo("top", false) end
	return true
end

function Controller:advance()
	if not self.model:next() then return false end
	return self:turn()
end

function Controller:retreat()
	if not self.model:back() then return false end
	return self:turn()
end

function Controller:chooseAudience(id)
	if not self.model:setAudience(id) then return false end
	self:refresh()
	return true
end

function Controller:chooseWorld(genre)
	if not self.model:toggleInterest(genre) then return false end
	self:refresh()
	return true
end

function Controller:startRecommended()
	local game = self.model:recommend(self.adventures)
	self:finish()
	if game then return self.openSession(game.id) end
	return true
end

function Controller:finish()
	self.model:complete()
	self:persist()
	local sheet = self.sheet
	self.sheet, self.refs, self.page = nil, nil, nil
	if sheet then self.dismissSheet(sheet) end
	return true
end

return Controller
