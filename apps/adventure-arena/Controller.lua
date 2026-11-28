local Session = require("apps.adventure-arena.zilscript.zilscript.reader.Session")
local JsonDocument = require("apps.adventure-arena.services.JsonDocument")
local Store = require("apps.adventure-arena.Store")
local ReadingSettings = require("apps.adventure-arena.models.ReadingSettings")
local Words = require("apps.adventure-arena.services.Words")
local ZILRuntime = require("apps.adventure-arena.services.ZILRuntime")
local PageHost = require("apps.adventure-arena.controllers.PageHost")
local OnboardingController = require("apps.adventure-arena.controllers.OnboardingController")
local ReadingSettingsController = require("apps.adventure-arena.controllers.ReadingSettingsController")
local SessionController = require("apps.adventure-arena.controllers.SessionController")
local Template = require("ui.template")
local xml = require("ui.xml")

local VIEWS = "apps/adventure-arena/views/"
local DOCUMENTS = {
	saves = "adventure-arena/saves.json",
	reading = "adventure-arena/reading.json",
	onboarding = "adventure-arena/onboarding.json",
}

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	options = options or {}
	local ns = options.ns or require("ns")
	local readFile = ns._readFile
	local sessionModel = options.sessionModel or Session.new {
		engineFactory = options.engineFactory or function(game, seed)
			return ZILRuntime.new(game, readFile, seed)
		end,
	}
	local self = setmetatable({ ns = ns, sessionModel = sessionModel }, Controller)
	-- The app's words in the language it speaks now; every render takes them.
	local function resources() return Words.load(ReadingSettings.language()) end
	self.resources = resources
	local function mountTemplate(host, template)
		return Template.new(host, VIEWS .. template .. ".etlua", ns, resources)
	end
	-- Headless test runs never read or write the reader's real library.
	local function document(name)
		if rawget(_G, "__headless") then return {} end
		return JsonDocument.new(ns, name)
	end
	-- The store the models read: the catalog, the saves and the reader's
	-- settings, loaded from and written to their documents.
	local documents = options.documents or {}
	local language = options.language
	for _, argument in ipairs(rawget(_G, "arg") or {}) do
		language = language or argument:match("^%-%-language=(.+)$")
	end
	local preferredLanguages = options.preferredLanguages
	if not preferredLanguages and ns.preferredLanguages then preferredLanguages = ns.preferredLanguages() end
	self.store = Store.new {
		games = options.games,
		language = language,
		preferredLanguages = preferredLanguages,
		documents = {saves = documents.saves or document(DOCUMENTS.saves), reading = documents.reading or document(DOCUMENTS.reading)},
	}
	self.readingOptions = ReadingSettingsController.new {
		mountTemplate = mountTemplate,
		onChange = function() self.sessionController:applyReadingSettings() end,
	}
	local function push(template, data)
		return self:push(template, data)
	end
	-- What only the window can do for a page (pages/*.lua reads these as
	-- `self.app`).
	self.pages = PageHost.new(ns, {
		push = function(id, state) return self:pushPage(id, state) end,
		back = function() return self:back() end,
		openCatalogPage = function(id) return self:openCatalogPage(id) end,
		languageChanged = function() self:retitle() end,
		openSession = function(id, fresh) return self.sessionController:show(id, fresh) end,
		openGuide = function() self.onboarding:openGuide(self.window) end,
		mountReadingOptions = function(host) self:mountReadingOptions(host) end,
		resources = resources,
	})
	local function back() return self:back() end
	self.sessionController = SessionController.new {
		model = sessionModel,
		push = push,
		back = back,
		ns = ns,
		readingOptions = self.readingOptions,
		resources = resources,
		haptics = options.haptics or require("ui.haptics"),
		-- Dictation is the Speech plugin (src/plugins/speech), which the iOS
		-- hosts link; elsewhere the composer offers no microphone.
		speech = options.speech or (function()
			local ok, Speech = pcall(require, "Speech")
			return ok and Speech or nil
		end)(),
		after = options.after or function(seconds, callback)
			if type(ns.async) ~= "function" then return end
			ns.async(function()
				ns.sleep(seconds)
				callback()
			end)
		end,
		onClose = function() self.pages:refresh() end,
		renderTemplate = function(template, data)
			return self:render(template, data)
		end,
		mountTemplate = mountTemplate,
		presentSheet = function(sheet, detents, onDismiss)
			return ns.presentSheet(sheet, { parent = self.window, detents = detents, onDismiss = onDismiss })
		end,
		dismissSheet = function(sheet)
			if sheet then return ns.dismiss(sheet) end
		end,
	}
	self.onboarding = options.onboarding or OnboardingController.new {
		store = documents.onboarding or document(DOCUMENTS.onboarding),
		resources = resources,
		ns = ns,
		presentSheet = function(sheet, detents)
			return ns.presentSheet(sheet, { parent = self.window, detents = detents })
		end,
		dismissSheet = function(sheet)
			if sheet then return ns.dismiss(sheet) end
		end,
		openSession = function(id, fresh) return self.sessionController:show(id, fresh) end,
	}
	self.mountTemplate = mountTemplate
	return self
end

-- A view rendered once, with the app's words in the current language.
function Controller:render(template, data)
	local withWords = { resources = self.resources() }
	for key, value in pairs(data) do withWords[key] = value end
	return xml.renderFile(VIEWS .. template .. ".etlua", withWords, self.ns)
end

-- Screens are <Page> templates: title, toolbar and presentation are declared
-- there, so pushing is render-and-push. A page whose title is a word of the
-- app (Settings, Search) passes `title`, a function that names it in the
-- language of the moment, so that changing the language retitles the stack.
function Controller:push(template, data, title)
	local page, refs = self:render(template, data)
	self:pushTitled(page, title)
	return page, refs
end

-- `titles[n]` names stack page n (the root is 1); a page the user swiped away
-- leaves its entry behind, so the list is cut to the real stack first.
function Controller:pushTitled(page, title)
	for index = #self.titles, #self.ns.navigationPages(self.navigation) + 1, -1 do self.titles[index] = nil end
	self.navigation:push(page)
	self.titles[#self.ns.navigationPages(self.navigation)] = title or false
end

-- The app's language changed: the pages on screen that draw themselves once
-- (the navigation titles) are named again; mounted pages are asked again
-- by PageHost:refresh.
function Controller:retitle()
	local pages = self.ns.navigationPages(self.navigation)
	for index, page in ipairs(pages) do
		local title = self.titles[index]
		if title then page.title = title() end
	end
end

-- A page of a route pushed on the navigation stack that is showing.
function Controller:pushPage(id, state)
	local page, refs = self.pages:render(id, state)
	self:pushTitled(page)
	return page, refs
end

function Controller:back()
	self.sessionController:cancelDictation()
	self.navigation:pop()
end

function Controller:openCatalogPage(id)
	if id == "create" then return self:push("pages/Create", {}, function() return self.resources().create end) end

	local template, data
	if id == "search" then
		template, data = "pages/Search", self.pages:data("search")
	else
		assert(id == "settings", "unknown catalog page")
		template, data = "layouts/CatalogPage", { title = self.resources().settings, actions = {} }
	end
	data.actions.closeCatalogPage = function()
		if id == "settings" then
			self.readingOptions:unmount(self.catalogReadingOptions)
			self.catalogReadingOptions, self.readingHost = nil, nil
		end
		self.pages:unmount(id)
	end
	local _, refs = self:push(template, data, function() return self.resources()[id] end)
	self.pages:mount(id, refs.catalogContent)
end

function Controller:renderHome(template)
	local page = self.pages:page("discover")
	local config, refs = self:render(template, {
		actions = self.pages:actions("discover", page),
	})
	self.navigation = refs.navigation
	self.titles = { function() return self.resources().discover end }
	self.pages:mount("discover", refs.discoverContent)
	return config
end

-- The reading options are shared with the in-book sheet: mounted once per
-- host the Settings page draws.
function Controller:mountReadingOptions(host)
	if not host or self.readingHost == host then return end
	self.readingOptions:unmount(self.catalogReadingOptions)
	self.readingHost = host
	self.catalogReadingOptions = self.readingOptions:mount(host, true)
end

function Controller:home()
	self:renderHome("layouts/Home")
	return self.navigation
end

function Controller:createWindow()
	self.window = self.ns.Window(self:renderHome("layouts/Window"))
	-- Headless runs drive the tour themselves; a live launch shows it once.
	if not rawget(_G, "__headless") and self.onboarding:needed() then
		self.onboarding:open(self.window)
	end
	return self.window
end

return Controller
