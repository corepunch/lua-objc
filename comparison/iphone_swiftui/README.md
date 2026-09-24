# SwiftUI and lua-objc iPhone comparison

This folder contains one shared fixture contract and independent SwiftUI and
lua-objc compositions. Both apps read [contract.json](contract.json); the
contract fixes sample text, font sizes and weights, control styles and values,
fixture order, and the capture environment. The two view trees are implemented
separately so their output can be compared without sharing layout code.

The first comparison covers text styles and wrapping, SF Symbol labels, button
styles and disabled state, `VStack`/`HStack`/`ZStack` composition, and native
text field, toggle, slider, and progress controls. Each family is a launch
selectable fixture, which gives it the full iPhone viewport in the screenshot.

The reference app uses SwiftUI controls. The candidate app uses the public
lua-objc UIKit API and etlua templates. Both run on the same booted Simulator;
the capture script records the selected device and runtime and writes full
device screenshots for each fixture.

Build and capture all fixtures on the configured iPhone 17 Simulator:

```sh
comparison/iphone_swiftui/capture.sh all
```

Capture one fixture:

```sh
comparison/iphone_swiftui/capture.sh buttons
```

The generated image pairs and environment record live under
`captures/ios-26.5-iphone-17/`. Set `DEVICE` to another installed iPhone name
before capture; update the capture directory and contract metadata when making
a new baseline on a different device or OS runtime.

| Fixture | Focus | lua-objc composition |
|---|---|---|
| `labels` | Font sizes, weights, secondary text, wrapping, SF Symbol label | `views/Window.etlua` labels branch |
| `buttons` | Automatic, bordered, prominent, plain, symbol, disabled | `views/Window.etlua` buttons branch |
| `stacks` | Flexible horizontal spacing, nested stacks, symbol overlay | `views/Window.etlua` stacks branch |
| `controls` | Text field, toggle, slider, progress | `views/Window.etlua` controls branch |

The status bar is normalized to 9:41 with full signal and battery. Appearance,
locale, layout direction, and dynamic type are fixed in the contract and SwiftUI
host. The capture script also sets the Simulator to large content size and
disables increased contrast. The Simulator supplies the same OS build, screen
scale, safe area, and native UIKit controls to both captures.

The UIKit host safe-area inset is applied to the root `ScrollView` content
origin and scroll extent. The fixture app does not add an app-specific offset.
