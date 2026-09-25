---
layout: default
title: MeshGradient
---

# MeshGradient and TimelineView

lua-objc maps SwiftUI's iOS 18 `MeshGradient` and `TimelineView(.animation)`
onto a shared Core Graphics rasterizer plus a per-platform view that ticks
with `CADisplayLink`. Controllers do not rebuild the tree each frame.

## SwiftUI

```swift
TimelineView(.animation) { timeline in
    MeshGradient(
        width: 3,
        height: 3,
        points: [ /* SIMD2<Float> in 0...1 */ ],
        colors: [ /* Color */ ]
    )
}
.ignoresSafeArea()
.background(.black)
```

## lua-objc XML

```xml
<Window title="Mesh" background="black" ignoresSafeArea="all">
  <TimelineView schedule="animation" ignoresSafeArea="all" background="black">
    <MeshGradient width="3" height="3" animated="true">
      <MeshPoint x="0" y="0" red="0.01" green="0.01" blue="0.03" />
      <MeshPoint x="0.5" y="0" red="0.12" green="0.04" blue="0.28" />
      <MeshPoint x="1" y="0" red="0.02" green="0.02" blue="0.06" />
      <MeshPoint x="0" y="0.5" red="0.18" green="0.05" blue="0.22" />
      <MeshPoint x="0.5" y="0.5" red="0.85" green="0.78" blue="1.00" />
      <MeshPoint x="1" y="0.5" red="0.08" green="0.22" blue="0.55" />
      <MeshPoint x="0" y="1" red="0.00" green="0.00" blue="0.02" />
      <MeshPoint x="0.5" y="1" red="0.25" green="0.06" blue="0.18" />
      <MeshPoint x="1" y="1" red="0.01" green="0.02" blue="0.05" />
    </MeshGradient>
  </TimelineView>
</Window>
```

`ignoresSafeArea="all"` is `.ignoresSafeArea()` with no edge list.
`true` and `edges` are aliases. `background="black"` is `.background(.black)`.

## Lua constructors

```lua
local mesh = ns.MeshGradient({
    width = 3,
    height = 3,
    animated = true,
    points = { {0,0}, {0.5,0}, {1,0}, {0,0.5}, {0.5,0.5}, {1,0.5}, {0,1}, {0.5,1}, {1,1} },
    colors = { { red = 0.01, green = 0.01, blue = 0.03 }, -- one per point
    },
})
-- or wrap an existing mesh:
ns.TimelineView({ schedule = "animation", content = mesh, ignoresSafeArea = "all" })
```

Prefer the XML tag in an `.etlua` template. Keep view-tree construction out of
controllers.

## Animation

When `animated` is true the interior points follow:

- `x = 0.5 + 0.28 * sin(1.35 t)`
- `y = 0.5 + 0.24 * cos(1.05 t)`
- plus a small `sin(1.2 t)` offset on neighboring interior points

Corner points stay at `(0,0)`, `(1,0)`, `(0,1)`, `(1,1)` so the mesh keeps
covering the view. This matches the public iOS 18 tip, not a general
keyframe API.

## Files

| Role | Path |
|---|---|
| Rasterizer | `src/shared/mesh_gradient.m` |
| AppKit view | `src/appkit/mesh_gradient.m` |
| UIKit view | `src/uikit/mesh_gradient.m` |
| Demo | `demo/mesh-gradient/views/Window.etlua` |
| Tests | `tests/mesh_gradient.test.lua` |

`make run ARGS="demo/mesh-gradient"`
