# State and Invalidation

lua-objc state is ordinary Lua data on controllers and models. Property reads do
not establish subscriptions, and mutations do not trigger rendering by
themselves. Controllers explicitly invalidate after an action or model change.
This is an observation-shaped state invalidation contract; it does not port
Combine or Swift Observation.

## State Lives on the Controller

Local state—UI state, selection, form state, navigation—lives on the controller instance, not in framework-managed `@State` or `@Observable`.

```lua
local Controller = {}

function Controller.new(model)
    return setmetatable({
        model = model,
        
        -- UI state
        selectedItemId = nil,
        isEditing = false,
        searchText = "",
        showDetails = false,
    }, { __index = Controller })
end

function Controller:selectItem(id)
    self.selectedItemId = id
    self:updateUI()
end

function Controller:toggleEditing()
    self.isEditing = not self.isEditing
    self:updateUI()
end
```

## Views Observe State Through Templates

Controllers pass state to etlua templates. Views update when the controller
explicitly asks them to. Prefer updating a retained ref or a native collection
for a local change. A full window render rebuilds its view tree and should be
reserved for structural changes.

```xml
<VStack>
  <!-- Selected state controls visibility -->
  <% if selectedItemId then %>
    <DetailView itemId="<%= selectedItemId %>" />
  <% else %>
    <Label color="gray">No item selected</Label>
  <% end %>
  
  <!-- Editing mode changes UI -->
  <% if isEditing then %>
    <TextField value="<%= selectedItem.name %>" />
  <% else %>
    <Label><%= selectedItem.name %></Label>
  <% end %>
</VStack>
```

## When to Invalidate (Trigger Re-render)

Call a full-window `updateUI()` or `renderWindow()` only when:

1. **User action** — button tap, gesture, text input
2. **Model mutation** — item added/removed, status changed
3. **Async completion** — network response, file load done
4. **Navigation** — route change, sheet close

**Do not** invalidate on:
- Animation frames (animations run natively)
- Scroll events (scroll is native, just track position if needed)
- Every keystroke when the view does not need immediate feedback
- Reduce Motion / appearance changes (use system dark mode)

```lua
-- ❌ Bad: Invalidates on every scroll
function Controller:onScroll(offset)
    self.scrollPosition = offset
    self:updateUI()  -- DON'T DO THIS
end

-- ✅ Good: Track for later, invalidate only on action
function Controller:onScroll(offset)
    self.scrollPosition = offset
    -- No invalidation
end

function Controller:jumpToItem(id)
    self.scrollPosition = calculateScrollOffset(id)
    self:updateUI()  -- Invalidate once when intentional
end
```

## Binding Form Inputs

Text fields, toggles, and other inputs are bound via etlua attributes that feed into action callbacks.

```xml
<TextField
    value="<%= formData.name %>"
    onTextChange="updateName"
    placeholder="Name"
    />
```

```lua
function Controller:updateName(newValue)
    self.formData.name = newValue
    -- Buffer the edit; update a retained ref only if immediate feedback is needed.
end
```

## Environment-Like Values (No Context API)

For application-wide state (colors, size class, locale), keep them in the model or a global constants table:

```lua
-- Global constants (not on controller)
local COLORS = {
    accent = "#007AFF",
    background = "#FFFFFF",
    destructive = "#FF3B30",
}

-- Model-level configuration
local Model = {}

function Model.new()
    return {
        theme = "light",  -- "light" | "dark"
        locale = "en-US",
    }
end
```

Pass them to templates:

```xml
<Button
    title="Delete"
    style="destructive"
    color="<%= COLORS.destructive %>"
    action="delete"
    />
```

## No Props Drilling; Direct References

Because controllers retain view refs, you can wire actions directly without passing callbacks through every child:

```lua
function Controller:createWindow()
    local view, refs = xml.renderFile("views/Main.etlua", {
        items = self.model:allItems(),
        selectedItemId = self.selectedItemId,
        actions = {
            selectItem = function(id) self:selectItem(id) end,
            deleteItem = function(id) self:deleteItem(id) end,
        },
    })
    
    self.refs = refs
    return view
end

-- Later, update a specific ref directly without re-rendering the whole window
function Controller:updateItemUI(id)
    local itemRef = self.refs["item_" .. id]
    if itemRef then
        itemRef:update({
            selected = (self.selectedItemId == id),
            -- Other property updates
        })
    end
end
```

## Testing State

State is just a Lua table. Test it directly:

```lua
function testControllerState()
    local controller = createController()
    
    -- Initial state
    assert(controller.selectedItemId == nil)
    assert(controller.isEditing == false)
    
    -- Mutation
    controller:selectItem(42)
    assert(controller.selectedItemId == 42)
    
    -- Toggle
    controller:toggleEditing()
    assert(controller.isEditing == true)
end
```

## Common Patterns

### Form Data Collection

```lua
local Controller = {}

function Controller.new()
    return setmetatable({
        formData = {
            name = "",
            email = "",
            subscribe = false,
        },
    }, { __index = Controller })
end

function Controller:updateField(fieldName, value)
    self.formData[fieldName] = value
    -- No invalidation here; only on submit
end

function Controller:submitForm()
    -- Validate
    if not self.formData.name or self.formData.name == "" then
        self:showError("Name required")
        return
    end
    
    -- Send to model
    self.model:createUser(self.formData)
    
    -- Invalidate after action
    self:resetForm()
end

function Controller:resetForm()
    self.formData = { name = "", email = "", subscribe = false }
    self:updateUI()
end
```

### Tab Selection

```lua
function Controller.new()
    return setmetatable({
        selectedTab = "home",  -- Tab name
    }, { __index = Controller })
end

function Controller:selectTab(tabName)
    self.selectedTab = tabName
    self:updateUI()
end
```

### Detail View with Unrelated State Unchanged

```lua
function Controller:showItemDetail(itemId)
    -- Show detail WITHOUT affecting list selection or scroll position
    
    self.detailedItem = self.model:item(itemId)
    self.showDetail = true
    
    -- Only re-render the detail pane, not the whole window
    self:updateDetailPane()
end

function Controller:updateDetailPane()
    local refs = self.refs
    if refs.detailPane then
        refs.detailPane:update({
            item = self.detailedItem,
        })
    end
end

function Controller:closeDetail()
    self.showDetail = false
    self.detailedItem = nil
    self:updateDetailPane()
end
```

## Reduce Motion & Appearance

System preferences (dark mode, reduce motion) are detected but **not observed**. Check them only when needed:

```lua
function Controller:animateTransition(view, destination)
    -- Check user preference once per action
    if bridge._reduceMotionEnabled() then
        -- Instant transition
        view:update(destination)
    else
        -- Animated transition
        view:animate("opacity", { from = 1, to = 0, duration = 0.2 })
        -- ... animate in new view ...
    end
end
```

## Summary

| Pattern | Use | Avoid |
|---------|-----|-------|
| **Local state on controller** | Selection, form, UI mode | Shared global state |
| **Explicit invalidation** | After user action, model change | Every animation frame |
| **Template re-rendering** | Structural changes | Full-window updates on every keystroke |
| **Ref updates** | Single element changes | Re-rendering entire list |
| **Direct action callbacks** | Controllers call model directly | Props drilling |
| **Test as Lua table** | Verify state mutations | Mock framework |

No @State, no @ObservedObject, no Combine. Just controllers, models, and explicit invalidation. Simpler and faster.
