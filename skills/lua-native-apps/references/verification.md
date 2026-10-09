# Verification

Use the repository's real host and test commands. Headless tests catch behavior
regressions; screenshots and layout dumps catch native geometry and appearance
problems that headless tests cannot see.

## Fast headless checks

Every implementation or bug fix needs a focused `tests/*.test.lua` regression
and must be discovered by `make test`. Tests run with `_G.__headless = true`;
do not open windows or sleep to simulate loading. Cover empty and missing data,
zero sizes, overflow, mutation, and preservation of unrelated state when relevant.

```sh
make test
```

## Real AppKit screenshots

Build and launch the app through the actual host. Use the native screenshot flag
to capture the settled window:

```sh
make
./lua-objc --screenshot=/tmp/app-light.png --appearance=light apps/<app>/init.lua
./lua-objc --screenshot=/tmp/app-dark.png --appearance=dark apps/<app>/init.lua
./lua-objc --screenshot=/tmp/app-small.png --width=760 --height=468 apps/<app>/init.lua
```

Inspect each image. Check light and dark appearances, substantially smaller and
larger sizes, long text, selection, keyboard focus, and every relevant empty,
loading, disabled, and error state. For iOS streamed simulator work, use the
workflow in [`docs/ios.md`](../../../docs/ios.md); do not substitute environment
variables or a different screenshot command.

## Several pages and states in one launch

A restyle touches more than one page and more than one state. Write a capture
plan (`lua/ui/capture.lua`) that drives the app with its own methods and
captures each state; it writes `<prefix>.png` and `<prefix>.layout.xml`:

```lua
-- /tmp/plan.lua
return function(capture, app)
	for _, appearance in ipairs({"light", "dark"}) do
		capture.appearance(appearance)
		for _, id in ipairs({"overview", "map", "kinds"}) do
			app:show(id)
			capture.shot("/tmp/caps/" .. id .. "-" .. appearance)
		end
	end
	app:toggleChartStyle()
	app:show("map", {focus = "developer"})
	capture.shot("/tmp/caps/map-rectangles")
end
```

```sh
./lua-objc --capture-plan=/tmp/plan.lua --width=1100 --height=760 apps/diskmap/init.lua --showcase
./lua-objc --capture-plan=/tmp/plan.lua --width=950 --height=580 apps/diskmap/init.lua --showcase
```

Use the app's deterministic data (`--showcase` for Diskmap) so captures are
comparable. When the request names a reference page, capture it in the same
plan and compare the candidates against it region by region. Compare
geometry through the `.layout.xml` files; PNG diffs are noisy.

## Layout diagnosis

When an AppKit view clips, moves, or gets an unexpected size, inspect the
generated native hierarchy before changing layout values:

```sh
./lua-objc --dump-layout=/tmp/layout.xml apps/<app>/init.lua
rg -n 'cropped="true"|outsideParent="true"|contentClipped="true"' /tmp/layout.xml
./lua-objc --dump-layout=/tmp/layout-small.xml --width=760 --height=468 apps/<app>/init.lua
```

Inspect the affected node's computed frame, intrinsic/fitting size, clipping,
and parent geometry. Repeat the dump after the fix. Do not manually construct a
diagnostic hierarchy in application code.

## Test the changed surface

- Add new app entrypoints to `tests/examples.test.lua`.
- For container changes, test empty, zero-size, overflow, and unrelated state.
- For navigation, test push/pop and verify model state survives.
- For native controls, exercise focus, keyboard behavior, accessibility labels,
  and supported disabled/empty/error states.
- A passing test suite does not replace visual inspection for a UI change.
- Assert what the request says, in its terms (where a control lives, which
  pages share a template, which view contains which), not the variables your
  implementation happens to use.
