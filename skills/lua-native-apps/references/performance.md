# Performance Rules & Patterns

This guide teaches patterns that leverage native UIKit/AppKit advantages over React Native and SwiftUI. lua-objc's performance wins come from:

1. **Direct native layouts** — not a JS bridge or SwiftUI reflection
2. **Lua's speed** — faster than JS for business logic
3. **Smart invalidation** — templates only re-render changed data

## Core Rule: Virtualize Large Lists

Never render 1,000+ static items directly.

❌ **Bad: 1,000-item VStack test fails**
```lua
views["list.etlua"] = function()
    return [[
        <VStack>
        <% for _, item in ipairs(items) do %>
            <Label><%= item.name %></Label>
        <% end %>
        </VStack>
    ]]
end
```

✅ **Good: Use LazyVStack for scrollable content**
```xml
<ScrollView>
  <LazyVStack>
    <% for i=1, math.min(50, #items) do %>
      <ItemRow item="<%= items[i] %>" />
    <% end %>
  </LazyVStack>
</ScrollView>
```

✅ **Better: Use List for maximum performance**
```xml
<List ref="myList">
  <% for _, item in ipairs(items) do %>
    <ListRow>
      <Label><%= item.name %></Label>
    </ListRow>
  <% end %>
</List>
```

### VStack vs LazyVStack vs List

| Container | Best For | Max Items | Behavior |
|-----------|----------|-----------|----------|
| `VStack` | Fixed, small content (< 50 items) | ~100 | All views created at once |
| `LazyVStack` | Dynamic, medium lists (50–5k) | 5,000 | Views recycled as scrolled; visible bounds matter |
| `List` | Large or data-driven (5k+) | 100k+ | Native UITableView/NSTableView; best performance |

Choose by use case, not gut feeling:
- **Sidebar with 8 folders?** VStack.
- **Search results: 100–500 hits?** LazyVStack.
- **Mail inbox: 5,000+ messages?** List.

## Memory & GC

Lua tables and string allocations are fast, but large tables leak memory if not released.

### Release Container Models After Navigation

When you navigate away from a screen, release its model instance to allow GC:

```lua
function Controller:showDetail(id)
    local item = self.model:item(id)
    local window, refs = xml.renderFile("views/Detail.etlua", {
        item = item,
        actions = self.detailActions,
    }, ns)
    
    -- Store the window; release on close
    self.detailWindow = window
    window:on("close", function()
        self.detailWindow = nil  -- Allow GC of window + refs
    end)
    
    ns.Window(window)
end
```

### String Concatenation in Loops

Avoid building large strings in loops. Use `table.concat` instead:

❌ **Bad: O(n²) allocations**
```lua
local result = ""
for _, line in ipairs(lines) do
    result = result .. line .. "\n"  -- Reallocates each iteration
end
```

✅ **Good: Single allocation**
```lua
local lines = {}
for _, item in ipairs(data) do
    table.insert(lines, item.text)
end
local result = table.concat(lines, "\n")
```

## Render Invalidation

Templates are re-rendered only when:
1. The controller calls `xml.renderFile()` with new data
2. A ref target's properties are updated via `ref:update()`
3. A model mutation triggers a controller action

**Never** re-render a view on every scroll event or animation frame. Update model state, let the controller decide to invalidate.

### Update Views in Place Rather Than Re-render

When a small part of a list changes (e.g., one item's status), update the view directly:

❌ **Inefficient: Re-render entire list**
```lua
function Controller:markItemRead(id)
    table.insert(self.model.readItems, id)
    self.mainWindow = xml.renderFile("views/Main.etlua", ...)
    ns.Window(self.mainWindow)  -- Flickers
end
```

✅ **Better: Batch-update specific refs**
```lua
function Controller:markItemRead(id)
    self.model:markRead(id)
    if self.itemRefs[id] then
        self.itemRefs[id]:update({ isRead = true })
    end
end
```

See `examples/mail` for example of efficient list updates.

## Layout Performance

### Minimize Nested Containers

Deep nesting (10+ levels) causes layout recalculation cascades. Flatten where possible:

❌ **Deep nesting: 7+ layout passes**
```xml
<VStack>
  <HStack>
    <VStack>
      <HStack>
        <Image />
      </HStack>
    </VStack>
  </HStack>
</VStack>
```

✅ **Flattened: 2 layout passes**
```xml
<HStack>
  <Image />
  <VStack><!-- content --></VStack>
</HStack>
```

### Avoid Spacer + Fixed Height

❌ **Brittle + layout thrashing**
```xml
<VStack>
  <Label>Title</Label>
  <Spacer />
  <Label>Footer</Label>
  <!-- Height changes = re-layout -->
</VStack>
```

✅ **Use padding and align-to-edges**
```xml
<VStack>
  <Label>Title</Label>
  <Spacer />
  <Label>Footer</Label>
</VStack>
```

## Animation Performance

Core Animation runs off the main thread. Do **not** block the main thread in animations.

### Prefer System Animations

❌ **Custom JS-based animations (React Native pattern)**
```lua
-- Don't animate in Lua:
while elapsed < duration do
    view.opacity = interpolate(elapsed, duration)
    coroutine.yield()
end
```

✅ **Use native Core Animation**
```lua
-- Native animations run on render thread:
view:animate("opacity", { from = 0, to = 1, duration = 0.3 })
```

See `references/motion.md` for animation recipes.

## Asset & Image Handling

### Use Symbol Images Instead of PNGs

SF Symbols render smaller and sharper than bitmap assets:

❌ **Large PNG (20–100 KB per image)**
```xml
<Image named="icon_heart.png" />
```

✅ **SF Symbol (0 KB; system renders)**
```xml
<Image systemImage="heart.fill" color="red" />
```

### Cache Large Images

If your app loads 50+ unique images, keep a small cache:

```lua
local imageCache = {}
function Controller:getImage(url)
    if imageCache[url] then return imageCache[url] end
    local img = ns.loadImageFromURL(url)
    imageCache[url] = img
    if #imageCache > 100 then
        table.remove(imageCache, 1)  -- LRU eviction
    end
    return img
end
```

## Data Model Performance

### Query Only What You Display

Do not load all 100k users into memory if you only show 50 per page:

❌ **Loads entire database**
```lua
function Model:allUsers()
    return self.db:query("SELECT * FROM users")  -- Could be millions
end
```

✅ **Lazy pagination**
```lua
function Model:users(page, perPage)
    local offset = (page - 1) * perPage
    return self.db:query("SELECT * FROM users LIMIT ? OFFSET ?",
        perPage, offset)
end
```

### Index Your Queries

If your model frequently looks up items by ID, add an index:

```lua
function Model:new(db)
    self.db = db
    self.itemsById = {}
    for _, item in ipairs(db:query("SELECT * FROM items")) do
        self.itemsById[item.id] = item
    end
end

function Model:item(id)
    return self.itemsById[id]  -- O(1) instead of O(n)
end
```

## Profiling & Testing

### Benchmark Lists with --benchmark

Before shipping a feature, test it with 1,000+ items:

```bash
./lua-objc --benchmark examples/myapp/init.lua
```

This will:
1. Render a list with 1k items
2. Simulate scroll events
3. Measure frame time and report jank

### Use --dump-layout to Check View Hierarchy

Deeply nested or over-complex hierarchies show up here:

```bash
./lua-objc --dump-layout=/tmp/layout.xml examples/myapp/init.lua
```

Check for:
- Views with no `width` or `height` set (implicit wrapping)
- 10+ nested containers
- Large numbers of views at one level

### Headless Tests with perf assertions

In your test suite, measure invalidation time:

```lua
local function testListPerf()
    local controller = createController()
    local start = os.clock()
    controller:appendItems(table.range(1, 5000))
    local elapsed = (os.clock() - start)
    assert(elapsed < 0.5, "append 5k items took " .. elapsed .. "s")
end
```

## Summary

| Problem | Solution |
|---------|----------|
| 1k+ items on screen | Use `List` with pagination |
| Slow layout | Flatten nesting; use `ref:update()` |
| Memory bloat | Release window refs; use `table.concat` |
| Animation jank | Use native Core Animation |
| Large images | Use SF Symbols or resize to display size |
| Slow queries | Index frequently-accessed fields; paginate |
