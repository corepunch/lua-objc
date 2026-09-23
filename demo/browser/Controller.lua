local Model = require("demo.browser.Model")
local WebPage = require("ui.webpage")
local xml = require("ui.xml")
local ns = require("ns")

local Controller = {}

function Controller.new()
    return setmetatable({
        model = Model.new(),
        page = WebPage.new("https://example.com"),
        urlInput = "https://example.com",
        searchQuery = "",
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

function Controller:setSearchQuery(query)
    self.searchQuery = query or ""
end

function Controller:findNext()
    if self.searchQuery == "" then return end
    self.page:find(self.searchQuery, { wraps = true }, function(found)
        self.lastFindMatch = found
    end)
end

function Controller:zoomIn()
    self.page:setPageZoom(math.min(3, self.page.pageZoom + 0.25))
end

function Controller:zoomOut()
    self.page:setPageZoom(math.max(0.5, self.page.pageZoom - 0.25))
end

function Controller:goHome()
    self:navigate(self.model.homepageURL)
end

function Controller:toggleFavorites()
    self.showFavorites = not self.showFavorites
end

function Controller:createWindow()
    local config, refs = xml.renderFile("demo/browser/views/Main.etlua", {
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
            setSearchQuery = function(query) self:setSearchQuery(query) end,
            findNext = function() self:findNext() end,
            zoomIn = function() self:zoomIn() end,
            zoomOut = function() self:zoomOut() end,
            goHome = function() self:goHome() end,
            toggleFavorites = function() self:toggleFavorites() end,
        },
    }, ns)
    self.refs = refs
    self.window = ns.Window(config)
    return self.window
end

return Controller
