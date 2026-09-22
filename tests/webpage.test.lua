local function testWebPage()
    _G.__headless = true
    package.path = "./?.lua;" .. package.path

    local WebPage = require("ui.webpage")

    -- Test 1: Create WebPage
    local page = WebPage.new("https://example.com")
    assert(page:getURL() == "https://example.com", "URL should be set")
    print("✓ WebPage creation")

    -- Test 2: Initial state
    assert(page:getTitle() == "Loading...", "Title should start with Loading...")
    assert(page.progress == 0, "Progress should start at 0")
    assert(page.isLoading == false, "Should not be loading initially")
    print("✓ Initial state")

    -- Test 3: Load progress
    page:_setProgress(0.5)
    assert(page.progress == 0.5, "Progress should update")
    page:_setProgress(1.5)  -- Out of range
    assert(page.progress == 1, "Progress should be clamped to 1")
    print("✓ Progress updates")

    -- Test 4: Title updates
    page:_setTitle("Example Domain")
    assert(page:getTitle() == "Example Domain", "Title should update")
    print("✓ Title updates")

    -- Test 5: Loading state
    page:_didFinishLoad()
    assert(page.isLoading == false, "Should finish loading")
    assert(page.progress == 1, "Progress should be 1 when done")
    print("✓ Loading completion")

    -- Test 6: Navigation history
    assert(not page:canGoBack(), "Cannot go back on first page")
    assert(not page:canGoForward(), "Cannot go forward yet")

    page:loadURL("https://github.com")
    assert(page:canGoBack(), "Should be able to go back after navigation")
    assert(not page:canGoForward(), "Still cannot go forward")
    print("✓ Navigation history")

    -- Test 7: Go back
    page:goBack()
    assert(page:getURL() == "https://example.com", "Should go back to first URL")
    assert(not page:canGoBack(), "Cannot go back further")
    assert(page:canGoForward(), "Should be able to go forward")
    print("✓ Go back")

    -- Test 8: Go forward
    page:goForward()
    assert(page:getURL() == "https://github.com", "Should go forward")
    assert(not page:canGoForward(), "Cannot go forward again")
    print("✓ Go forward")

    -- Test 9: Reload
    local reloadURL = page:getURL()
    page:reload()
    assert(page.isLoading == true, "Should be loading after reload")
    assert(page:getURL() == reloadURL, "URL should not change on reload")
    print("✓ Reload")

    -- Test 10: Stop loading
    page:stop()
    assert(page.isLoading == false, "Should stop loading")
    print("✓ Stop loading")

    -- Test 11: Observer callback
    local called = false
    page:observe(function(prop, value)
        called = true
    end)
    page:_setTitle("Test")
    assert(called, "Observer should be called")
    print("✓ Observer callbacks")

    -- Test 12: Get history
    local page2 = WebPage.new("https://example.com")
    page2:loadURL("https://github.com")
    page2:loadURL("https://apple.com")
    local history = page2:getHistory()
    assert(#history == 3, "History should have 3 entries")
    assert(history[3].isCurrent == true, "Last entry should be current")
    print("✓ History tracking")

    -- Test 13: Error handling
    page:_didFailLoad("Network error")
    assert(page.isLoading == false, "Should stop loading on error")
    assert(page:getTitle():find("Error"), "Title should indicate error")
    print("✓ Error handling")

    -- Test 14: Multiple navigations don't create duplicate history
    local page3 = WebPage.new("https://example.com")
    page3:loadURL("https://example.com")
    local hist = page3:getHistory()
    assert(#hist == 1, "Should not duplicate same URL in history")
    print("✓ No duplicate history")

    print("\nAll WebPage tests passed!")
    return true
end

os.exit(testWebPage() and 0 or 1)
