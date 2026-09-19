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

    print("\nAll navigation tests passed!")
    return true
end

return {
    run = testNavigation,
}
