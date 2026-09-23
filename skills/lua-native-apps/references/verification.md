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
