local Model = require("apps.browser.Model")
local WebPage = require("ui.webpage")
local xml = require("ui.xml")
local ns = require("ns")

local Controller = {}

function Controller.new()
    return setmetatable({
        model = Model.new(),
        page = WebPage.new("https://example.com"),
        urlInput = "https://example.com",
        showFavorites = false,
    }, { __index = Controller })
end

function Controller:navigate(url)
    if url and url ~= "" then
        self.urlInput = url
        self.page:loadURL(url)
    end
end

function Controller:navigateFavorite(url)
    self:navigate(url)
    self.showFavorites = false
end

function Controller:goBack()
    if self.page:canGoBack() then
        self.page:goBack()
    end
end

function Controller:goForward()
    if self.page:canGoForward() then
        self.page:goForward()
    end
end

function Controller:reload()
    self.page:reload()
end

function Controller:goHome()
    self:navigate(self.model.homepageURL)
end

function Controller:toggleFavorites()
    self.showFavorites = not self.showFavorites
end

function Controller:createWindow()
    local config, refs = xml.renderFile("apps/browser/views/Main.etlua", {
        page = self.page,
        urlInput = self.urlInput,
        showFavorites = self.showFavorites,
        favorites = self.model.favoriteURLs,
        canGoBack = self.page:canGoBack(),
        canGoForward = self.page:canGoForward(),
        actions = {
            navigate = function(url) self:navigate(url) end,
            navigateFavorite = function(url) self:navigateFavorite(url) end,
            goBack = function() self:goBack() end,
            goForward = function() self:goForward() end,
            reload = function() self:reload() end,
            goHome = function() self:goHome() end,
            toggleFavorites = function() self:toggleFavorites() end,
        },
    }, ns)
    self.refs = refs
    self.window = ns.Window(config)
    return self.window
end

return Controller
