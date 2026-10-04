# Mac App Store build and upload

Diskmap is a macOS-only app. The checked-in `Diskmap.xcodeproj` has native targets for the app launcher, AppKit runtime, and StorageScan plugin. Native sources come from synchronized folders (`src`, `vendor/lua-5.4.8/src`), with exception sets naming the unity roots each target compiles. A single "Copy Lua" Run Script phase rsyncs the `.lua`, `.etlua`, and `.bin` files of `lua/` and `apps/diskmap/` into `Contents/Resources`, so new files need no project edit.

The launcher target sets `OTHER_LDFLAGS = -Wl,-needed_framework,CoreServices`. Keep it when recreating the project: the launcher is plain C and only dlopens `AppKit.dylib`, and inside the App Sandbox LaunchServices gets its `launchservicesd` lookup extension only when it is loaded at process start. Without the flag every Finder or `open` launch of the sandboxed bundle aborts in `+[NSApplication sharedApplication]` (`_RegisterApplication` cannot get an ASN), while `make run-diskmap` and Xcode debugger launches still work, which hides the bug. `tests/diskmap_xcode.test.lua` checks for the flag.

## Build

From the repository root:

```sh
make diskmap-xcode-build
```

The app bundle is `build/xcode-derived/Products/Release/Diskmap.app`. Open `apps/diskmap/Diskmap.xcodeproj` directly in Xcode to archive for generic macOS with the developer's Apple Distribution team, then use Xcode Organizer's **Distribute App → App Store Connect → Upload**. Current bundled runtime dylibs are arm64, so this build supports Apple Silicon Macs only; add x86_64 runtime slices before promising Intel compatibility.

## App Store Connect materials

Listing copy is in `store-assets/en/metadata.md`. Six 2560 × 1600 showcase screenshots are in `store-assets/en/screenshots/`; `make diskmap-store-screenshots` recaptures them. The preview video `/Users/igor/Desktop/Diskmap-Showreel.mp4` is 1920 × 1080 H.264, 30 seconds, and below Apple's 500 MB limit.

The App Store icon comes from `Assets.xcassets/AppIcon.appiconset/`. The App Store Connect preview is `/Users/igor/Desktop/Diskmap-Showreel.mp4` (30 seconds, 1920 × 1080, H.264). The privacy policy is published at https://github.com/corepunch/lua-objc/blob/main/apps/diskmap/PRIVACY.md and that URL is entered in App Store Connect.

The App Privacy declaration is published as **Data Not Collected**. Diskmap keeps scan results, preferences, history, and its operations log on the Mac. Its duplicate finder uses Apple's CommonCrypto SHA-256 implementation locally and the app has no network collection path. `Info.plist` sets `ITSAppUsesNonExemptEncryption` to false because the app relies only on Apple-provided encryption APIs.

## Important sandbox check

The App Store target has the required App Sandbox and user-selected read/write capability. Full Disk Access cannot be granted by an entitlement or by the app; the user must enable it in System Settings. Before review, test the signed sandboxed build's scan, open-folder, and cleanup behavior both with and without Full Disk Access. The local unsandboxed build is not proof that the App Store version can measure all locations.

## App Store Connect progress

The macOS app record uses bundle ID `org.luaobjc.diskmap`, SKU `DISKMAP-MAC-001`, and version 1.0. Its title is **Diskmap - Storage Optimization** because “Diskmap” alone was unavailable. The record has the English listing copy, Utilities category, 4+ rating, content-rights answer, published **Data Not Collected** label, support URL, five showcase screenshots, and one 30-second app preview. Release is set to manual.

Completed listing settings include the public privacy-policy URL, $4.99 USD base price with all 175 storefronts selected, copyright `Copyright © 2026 Igor Chernakov`, and the supplied App Review contact. A valid Apple Distribution identity is still required to sign and upload. The current local build succeeds, but is only locally signed. After upload, select the processed build and leave the version in **Prepare for Submission**; release is set to manual.

## Upload flow

1. Build the Release target using the command above.
2. Archive `Diskmap` for generic macOS using the seller's Apple Distribution team.
3. In Xcode Organizer, choose **Distribute App → App Store Connect → Upload** and wait for processing.
4. In the version's App Store Connect page, select the processed build.
5. Keep release on manual and stop at **Prepare for Submission**.
