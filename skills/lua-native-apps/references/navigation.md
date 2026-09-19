# Navigation Recipes in etlua & Lua

Navigation in lua-objc follows native platform patterns, not web routing. The controller owns navigation state and renders different templates in response to user actions.

## iOS: NavigationStack

Push-pop navigation stack similar to UINavigationController.

### Basic Usage

```xml
<!-- views/Root.etlua -->
<NavigationStack ref="navStack">
  <VStack>
    <Label>Inbox (20 messages)</Label>
    <Button title="Message 1" action="showMessage1" />
  </VStack>
</NavigationStack>
```

```lua
-- Controller.lua
function Controller:showMessage(id)
    local message = self.model:message(id)
    -- Push new screen: render template and push to nav stack
    local detail, refs = xml.renderFile("views/MessageDetail.etlua", {
        message = message,
        actions = self.detailActions,
    }, ns)
    self.navStack:push(detail)  -- Animates onto screen
end

function Controller:detailActions()
    return {
        back = function()
            self.navStack:pop()  -- Animates off screen
        end,
    }
end
```

### Navigation State

The navigation stack is a Lua table of rendered views:

```lua
-- Access the stack
local stackDepth = #self.navStack
local currentView = self.navStack[stackDepth]

-- Update the top view without popping
function Controller:updateCurrentView(newData)
    local current = xml.renderFile("views/Current.etlua", newData, ns)
    self.navStack:replaceTop(current)  -- Replace top without animation
end
```

### Conditional Navigation (Root vs Push)

Some views are roots, others are details:

```lua
function Controller:navigate(itemType, id)
    if itemType == "folder" then
        -- Root-level navigation: replace entire app
        self:showFolder(id)
    else
        -- Nested navigation: push onto stack
        self:showMessage(id)
    end
end

function Controller:showFolder(id)
    -- This is a root screen: clear nav stack and render
    local folder = self.model:folder(id)
    local root, refs = xml.renderFile("views/FolderView.etlua", {
        folder = folder,
        actions = self.folderActions,
    }, ns)
    self.navWindow = ns.Window(root)  -- New window root
end
```

## macOS: Split View (Sidebar + Detail)

Master-detail layout using NSplitView.

### Basic Usage

```xml
<!-- views/Main.etlua -->
<HSplit>
  <!-- Sidebar -->
  <VStack>
    <SearchField placeholder="Search files" />
    <List ref="fileList">
      <% for _, file in ipairs(files) do %>
        <ListRow>
          <Label><%= file.name %></Label>
        </ListRow>
      <% end %>
    </List>
  </VStack>
  
  <!-- Detail pane -->
  <VStack ref="detailPane">
    <% if selectedFile then %>
      <Label size="18" weight="bold"><%= selectedFile.name %></Label>
      <TextEditor value="<%= selectedFile.content %>" />
    <% else %>
      <Label color="gray">Select a file to view</Label>
    <% end %>
  </VStack>
</HSplit>
```

### Controller Pattern

```lua
function Controller:selectFile(id)
    local file = self.model:file(id)
    self.selectedFile = file
    
    -- Re-render detail pane only
    local detail, refs = xml.renderFile("views/DetailPane.etlua", {
        file = file,
    }, ns)
    
    self.detailRefs.detailPane:update(detail)
end
```

## Sheets & Modals

Present temporary UI on top of the current screen.

### Modal Sheet (iOS)

```lua
function Controller:showSettings()
    local sheet, refs = xml.renderFile("views/SettingsSheet.etlua", {
        settings = self.model:getSettings(),
        actions = self.settingsActions,
    }, ns)
    
    -- Open as modal sheet
    local sheetWindow = ns.Window({
        content = sheet,
        mode = "sheet",  -- Modal presentation
        animated = true,
    })
    
    self.settingsWindow = sheetWindow
end

function Controller:settingsActions()
    return {
        close = function()
            self.settingsWindow:close()
            self.settingsWindow = nil
        end,
        save = function()
            -- Handle save...
            self.settingsWindow:close()
        end,
    }
end
```

### Popover (macOS)

```lua
function Controller:showPopover(fromButton)
    local menu, refs = xml.renderFile("views/ContextMenu.etlua", {
        items = self.model:menuItems(),
        actions = self.popoverActions,
    }, ns)
    
    -- Show as popover near button
    ns.showPopover(menu, {
        anchorView = fromButton,
        direction = "down",
        maxWidth = 200,
    })
end
```

## Tabs

Tab-based interface (similar to UITabBarController).

### Basic TabView

```xml
<!-- views/MainTabs.etlua -->
<TabView>
  <!-- First tab -->
  <VStack systemImage="house" label="Home">
    <Label>Home feed</Label>
  </VStack>
  
  <!-- Second tab -->
  <VStack systemImage="magnifyingglass" label="Search">
    <SearchField />
  </VStack>
  
  <!-- Third tab -->
  <VStack systemImage="person.fill" label="Profile">
    <Label>Profile details</Label>
  </VStack>
</TabView>
```

### Tab Controller

Tabs usually don't need controller-level management (they're self-contained), but you can observe tab changes:

```lua
function Controller:createWindow()
    local mainUI, refs = xml.renderFile("views/MainTabs.etlua", {
        actions = {},
    }, ns)
    
    self.mainWindow = ns.Window(mainUI)
    
    -- Listen for tab changes (if TabView exposes events)
    if refs.tabView then
        refs.tabView:on("didSelectTab", function(index)
            -- Log tab change or prefetch data for next tab
            print("Selected tab " .. index)
        end)
    end
end
```

## Conditional Routes (Onboarding vs Main)

At app startup, show different screens based on state:

```lua
function Controller:createWindow()
    local isFirstLaunch = self.model:isFirstLaunch()
    
    if isFirstLaunch then
        -- Show onboarding flow
        self.mainWindow = self:createOnboarding()
    else
        -- Show main app
        self.mainWindow = self:createMainApp()
    end
end

function Controller:createOnboarding()
    local screen, refs = xml.renderFile("views/Onboarding.etlua", {
        actions = self.onboardingActions,
    }, ns)
    
    return ns.Window(screen)
end

function Controller:onboardingActions()
    return {
        complete = function()
            -- Mark onboarding done
            self.model:setFirstLaunchDone()
            -- Rebuild main window
            self.mainWindow = self:createMainApp()
        end,
    }
end
```

## State Preservation Across Navigation

When popping back to a screen, preserve its scroll position and selection:

```lua
function Controller:new(model, ns)
    self.model = model
    self.ns = ns
    self.scrollPositions = {}  -- { screenName -> scrollY }
    self.selections = {}       -- { screenName -> selectedId }
end

function Controller:showMessageList()
    local savedScrollY = self.scrollPositions["messageList"] or 0
    
    local list, refs = xml.renderFile("views/MessageList.etlua", {
        messages = self.model:messages(),
        actions = self.messageListActions,
    }, ns)
    
    refs.list:scrollTo(savedScrollY)
    
    self.messageListWindow = ns.Window(list)
    self.messageListRefs = refs
end

function Controller:messageListActions()
    return {
        showMessage = function(id)
            -- Save scroll position before navigating away
            self.scrollPositions["messageList"] = self.messageListRefs.list:currentScrollY()
            self:showMessageDetail(id)
        end,
        
        selectItem = function(id)
            self.selections["messageList"] = id
        end,
    }
end

function Controller:popBack()
    -- Restore saved state when returning
    self:showMessageList()
    if self.selections["messageList"] then
        self.messageListRefs.list:selectRow(self.selections["messageList"])
    end
end
```

## Deep Linking

Handle URLs or external intents that specify a navigation path:

```lua
function Controller:handleDeepLink(path)
    -- Parse path: "messages/123"
    local parts = {}
    for part in path:gmatch("([^/]+)") do
        table.insert(parts, part)
    end
    
    if parts[1] == "messages" and parts[2] then
        local messageId = tonumber(parts[2])
        self:showMessage(messageId)
    elseif parts[1] == "settings" then
        self:showSettings()
    end
end

-- At app launch, check for passed URL
function Controller:createWindow()
    local deepLink = os.getenv("APP_DEEP_LINK")
    if deepLink then
        self:handleDeepLink(deepLink)
    else
        self:showDefaultScreen()
    end
end
```

## Common Patterns

### Dismissing Sheets with Confirmation

```lua
function Controller:closeWithConfirm()
    local confirm, refs = xml.renderFile("views/ConfirmDialog.etlua", {
        title = "Unsaved changes",
        message = "Discard changes?",
        actions = {
            discard = function()
                self.settingsWindow:close()
            end,
            keep = function()
                confirm:close()
            end,
        },
    }, ns)
    
    ns.showAlert(confirm)
end
```

### Animated Transitions

Let the native platform handle transitions; the controller doesn't specify timing:

```lua
-- Good: Let platform animate
self.navStack:push(detailView)  -- Platform handles slide animation

-- Bad: Inventing animations in Lua
for i = 1, 20 do
    view.opacity = i / 20
    coroutine.yield()
end
```

## Testing Navigation

```lua
-- tests/navigation.test.lua
function testNavigationStack()
    local controller = createController()
    
    -- Verify initial state
    assert(#controller.navStack == 1, "Should have root screen")
    
    -- Push a view
    controller:showDetail(1)
    assert(#controller.navStack == 2, "Should push onto stack")
    
    -- Pop back
    controller:navStack:pop()
    assert(#controller.navStack == 1, "Should pop back to root")
end

function testSheetPresentation()
    local controller = createController()
    
    -- Present sheet
    controller:showSettings()
    assert(controller.settingsWindow ~= nil, "Should open settings")
    
    -- Close sheet
    controller.settingsWindow:close()
    assert(controller.settingsWindow == nil, "Should clean up after close")
end
```

## Key Rules

1. **Controller owns navigation state** — not the view
2. **Render templates per screen** — don't create mega-templates with all routes
3. **Release windows on close** — allow GC of refs and state
4. **Let platform animate** — don't invent transitions in Lua
5. **Preserve state when returning** — save scroll/selection before navigating
6. **Test navigation paths** — headless tests can call controller actions directly
