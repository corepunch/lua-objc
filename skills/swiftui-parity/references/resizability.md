# Resizability

There is no iPhone Duo hinge, reserved-region, or vertical-bar API in this bridge. Do not detect a device. Size the window the host actually gave the app.

- Read safe area with `<SafeAreaInset>` or `ignoresSafeArea`. Do not pad by a constant copied from one phone.
- `containerRelativeWidth` is the relative-width tool. Do not read `UIScreen.main` or cache one screen size.
- Before calling a layout change done, dump default and minimum sizes:

```sh
./lua-objc --dump-layout=/tmp/layout.xml apps/<app>/init.lua
./lua-objc --dump-layout=/tmp/layout-small.xml --width=760 --height=468 apps/<app>/init.lua
rg -n 'cropped="true"|outsideParent="true"|contentClipped="true"' /tmp/layout.xml /tmp/layout-small.xml
```

- A control that clips, falls outside its parent, or disappears only at the smaller size is a finding.
- Folding-specific SwiftUI (`toolbarVerticalEdge`, `ArrangementView`, asymmetric outer corners) is a gap. Record it in `gaps.md`. Do not approximate it with a second column of hard-coded offsets.
