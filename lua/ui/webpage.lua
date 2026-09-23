--[[
  ui/webpage.lua — Observable WebPage state for WebView integration

  Represents a web page with observable properties: title, progress, URL, history.
  Controllers can bind these to etlua templates for live updates.

  Usage:
    local WebPage = require("ui.webpage")
    local page = WebPage.new("https://example.com")
    -- page.title, page.progress, page.url observed by view layer
    page:goBack()
]]

local WebPage = {}
WebPage.__index = WebPage
local notifyObservers

function WebPage.new(url)
    if type(url) == "table" then url = url.url end
    local self = setmetatable({
        url = url or "",
        title = "Loading...",
        progress = 0,
        isLoading = false,

        -- Internal state
        _history = {},
        _historyIndex = 1,
        _observers = {},
    }, WebPage)

    -- Add initial URL to history
    if url and url ~= "" then
        self._history[1] = url
    end

    return self
end

-- Bind a native WKWebView without making it part of the domain model.
function WebPage:_attachNative(view, action)
    self._nativeView = view
    self._nativeAction = function(name, ...)
        action(view, name, ...)
    end
end

function WebPage:_nativeEvent(event, value)
    if event == "state" and type(value) == "table" then
        for _, key in ipairs({ "url", "title", "progress" }) do
            if value[key] ~= nil and self[key] ~= value[key] then
                self[key] = value[key]
                notifyObservers(self, key)
            end
        end
        self._nativeCanGoBack = value.canGoBack
        self._nativeCanGoForward = value.canGoForward
    elseif event == "loading" then
        self.isLoading = value == true
        notifyObservers(self, "isLoading")
    elseif event == "error" then
        self:_didFailLoad(value)
    end
end

-- Notify observers that a property changed
notifyObservers = function(self, propertyName)
    for _, callback in ipairs(self._observers) do
        if type(callback) == "function" then
            callback(propertyName, self[propertyName])
        end
    end
end

-- Subscribe to changes
function WebPage:observe(callback)
    if type(callback) == "function" then
        table.insert(self._observers, callback)
    end
end

-- Load a URL
function WebPage:loadURL(url)
    if url and url ~= "" then
        self.url = url
        self.title = "Loading..."
        self.progress = 0
        self.isLoading = true

        -- Add to history if different from current
        if self._history[self._historyIndex] ~= url then
            -- Truncate forward history when navigating
            for i = #self._history, self._historyIndex + 1, -1 do
                table.remove(self._history)
            end
            table.insert(self._history, url)
            self._historyIndex = #self._history
        end

        notifyObservers(self, "url")
        notifyObservers(self, "title")
        notifyObservers(self, "progress")
        notifyObservers(self, "isLoading")
        if self._nativeAction then self._nativeAction("load", url) end
    end
end

-- Called by native layer as page loads
function WebPage:_setProgress(value)
    self.progress = math.max(0, math.min(1, value or 0))
    notifyObservers(self, "progress")
end

-- Called by native layer when page title updates
function WebPage:_setTitle(newTitle)
    self.title = newTitle or self.title
    notifyObservers(self, "title")
end

-- Called by native layer when page finishes loading
function WebPage:_didFinishLoad()
    self.isLoading = false
    self.progress = 1
    notifyObservers(self, "isLoading")
    notifyObservers(self, "progress")
end

-- Called by native layer when page fails to load
function WebPage:_didFailLoad(error)
    self.isLoading = false
    self.title = "Error: " .. (error or "Page failed to load")
    notifyObservers(self, "isLoading")
    notifyObservers(self, "title")
end

-- Navigate back in history
function WebPage:goBack()
    if self:canGoBack() then
        self._historyIndex = self._historyIndex - 1
        local prevURL = self._history[self._historyIndex]
        self.url = prevURL
        self.title = "Loading..."
        self.progress = 0
        self.isLoading = true
        notifyObservers(self, "url")
        notifyObservers(self, "title")
        notifyObservers(self, "progress")
        notifyObservers(self, "isLoading")
        if self._nativeAction then self._nativeAction("back") end
    end
end

-- Navigate forward in history
function WebPage:goForward()
    if self:canGoForward() then
        self._historyIndex = self._historyIndex + 1
        local nextURL = self._history[self._historyIndex]
        self.url = nextURL
        self.title = "Loading..."
        self.progress = 0
        self.isLoading = true
        notifyObservers(self, "url")
        notifyObservers(self, "title")
        notifyObservers(self, "progress")
        notifyObservers(self, "isLoading")
        if self._nativeAction then self._nativeAction("forward") end
    end
end

-- Check if back is possible
function WebPage:canGoBack()
    if self._nativeCanGoBack ~= nil then return self._nativeCanGoBack end
    return self._historyIndex > 1
end

-- Check if forward is possible
function WebPage:canGoForward()
    if self._nativeCanGoForward ~= nil then return self._nativeCanGoForward end
    return self._historyIndex < #self._history
end

-- Reload current page
function WebPage:reload()
    self.title = "Reloading..."
    self.progress = 0
    self.isLoading = true
    notifyObservers(self, "isLoading")
    if self._nativeAction then self._nativeAction("reload") end
end

-- Stop loading
function WebPage:stop()
    self.isLoading = false
    notifyObservers(self, "isLoading")
    if self._nativeAction then self._nativeAction("stop") end
end

-- Evaluate JavaScript (returns result to callback)
function WebPage:evaluateJavaScript(script, callback)
    assert(type(script) == "string", "evaluateJavaScript requires a script string")
    if not self._nativeAction then
        if type(callback) == "function" then callback(nil, "WebPage is not attached to a WebView") end
        return false
    end
    self._nativeAction("evaluateJavaScript", script, callback)
    return true
end

-- Get current URL
function WebPage:getURL()
    return self.url
end

-- Get current title
function WebPage:getTitle()
    return self.title
end

-- Get loading progress (0.0 - 1.0)
function WebPage:getProgress()
    return self.progress
end

-- Get history as array of URLs
function WebPage:getHistory()
    local result = {}
    for i, url in ipairs(self._history) do
        result[i] = { url = url, isCurrent = (i == self._historyIndex) }
    end
    return result
end

return WebPage
