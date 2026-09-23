local function testNavigation()
    _G.__headless = true
    package.path = "./?.lua;" .. package.path

    local Navigation = require("ui.navigation")

    -- Test 1: Create navigation
    local nav = Navigation.new()
    assert(nav ~= nil)
    print("✓ Navigation creation")

    -- Test 2: Push destination
    nav:push("DetailView", { itemId = 42 })
    local current = nav:current()
    assert(current.name == "DetailView")
    assert(current.data.itemId == 42)
    print("✓ Push destination")

    -- Test 3: Pop destination
    nav:push("ListItemDetail", { id = 10 })
    nav:pop()
    current = nav:current()
    assert(current.name == "DetailView")
    print("✓ Pop destination")

    -- Test 4: Replace destination (one-way door)
    nav:replace("SearchView", {})
    current = nav:current()
    assert(current.name == "SearchView")
    print("✓ Replace destination")

    -- Test 5: Sheet presentation
    nav:presentSheet("FilterOptions", {
        detents = { "medium", "large" },
    })
    local sheet = nav:currentSheet()
    assert(sheet.name == "FilterOptions")
    assert(#sheet.detents == 2)
    print("✓ Present sheet")

    -- Test 6: Dismiss sheet
    nav:dismissSheet()
    sheet = nav:currentSheet()
    assert(sheet == nil)
    print("✓ Dismiss sheet")

    -- Value path retains domain values and resolves them through builders.
    local path = Navigation.Path.new()
    local unrelated = { selected = "inbox" }
    path:registerDestination("message", function(value) return value.id end)
    local native = {}
    local remove = Navigation.bindPath(path,
        function(value, builder) table.insert(native, (builder(value))) end,
        function() table.remove(native) end)
    path:push({ type = "message", id = 42, title = "Message" })
    assert(native[1] == 42 and path:current().id == 42)
    assert(unrelated.selected == "inbox")
    path:replace({ type = "message", id = 7 })
    assert(#native == 1 and native[1] == 7)
    path:pop()
    assert(#native == 0 and path:count() == 0)
    remove()
    print("✓ Value path push, replace, pop, and destination binding")

    print("\nAll navigation tests passed!")
    return true
end

os.exit(testNavigation() and 0 or 1)
