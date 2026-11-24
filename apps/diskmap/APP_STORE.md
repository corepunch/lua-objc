# Mac App Store build and upload

Diskmap is an Apple Silicon macOS app. The release Makefile builds its launcher, AppKit runtime, and StorageScan plugin with Clang. Packaging copies Lua and app resources into the bundle and compiles the app icon with `actool`.

The launcher links CoreServices at startup with `-Wl,-needed_framework,CoreServices` so App Sandbox grants the LaunchServices lookup before the launcher loads `AppKit.dylib`. The release tests check this linker flag.

## Build

From the repository root:

```sh
make diskmap-app
```

The local bundle is `build/local/diskmap/unsigned/Diskmap.app`.

## App Store Connect materials

See [the promotional materials guide](store-assets/README.md) for the gallery's design rationale, requirements, capture and video recipes, quality checks, and asc upload workflow.

Listing copy is in `store-assets/en/metadata.md`. Five 2880 × 1800 promotional screenshots are in `store-assets/en/screenshots/`, combining benefit headlines with complete native showcase windows. Regenerate them with `make diskmap-store-screenshots DISKMAP_STORE_PYTHON=/path/to/python3`, using a Python runtime with Pillow and NumPy. Captures, layout dumps and the contact sheet are in `build/diskmap-store/`.

The App Store icon comes from `Assets.xcassets/AppIcon.appiconset/`. `make diskmap-store-preview` converts the existing `build/Diskmap-Showreel.mov` into `apps/diskmap/store-assets/en/previews/Diskmap-AppStore-Preview.mov` (29.97 seconds, 1920 × 1080, 30 fps, H.264 High Level 4.0 and stereo AAC). The complete story is retained at a slightly faster pace, with audio pitch preserved. The privacy policy is published at https://github.com/corepunch/lua-objc/blob/main/apps/diskmap/PRIVACY.md and that URL is entered in App Store Connect.

The media were uploaded October 4, 2026 through the `corepunch` asc profile to English version 1.0. All six assets returned `COMPLETE`; subsequent reads verified their checksums, screenshot order and dimensions. Upload again with:

```sh
asc --profile corepunch screenshots upload \
  --version-localization 2935b7eb-1995-4d58-9574-5757a471087b \
  --path apps/diskmap/store-assets/en/screenshots --device-type DESKTOP \
  --replace --confirm --output json
asc --profile corepunch video-previews upload \
  --version-localization 2935b7eb-1995-4d58-9574-5757a471087b \
  --path apps/diskmap/store-assets/en/previews/Diskmap-AppStore-Preview.mov --device-type DESKTOP \
  --replace --confirm --output json
```

The App Privacy declaration is published as **Data Not Collected**. Diskmap keeps scan results, preferences, history, and its operations log on the Mac. Its duplicate finder uses Apple's CommonCrypto SHA-256 implementation locally and the app has no network collection path. `Info.plist` sets `ITSAppUsesNonExemptEncryption` to false because the app relies only on Apple-provided encryption APIs.

## Important sandbox check

The App Store target has the required App Sandbox and user-selected read/write capability. Full Disk Access cannot be granted by an entitlement or by the app; the user must enable it in System Settings. Before review, test the signed sandboxed build's scan, open-folder, and cleanup behavior both with and without Full Disk Access. The local unsandboxed build is not proof that the App Store version can measure all locations.

## App Store Connect progress

The macOS app record uses bundle ID `org.luaobjc.diskmap`, SKU `DISKMAP-MAC-001`, and version 1.0. Its title is **Diskmap - Storage Optimization** because “Diskmap” alone was unavailable. The record has the English listing copy, Utilities category, 4+ rating, content-rights answer, published **Data Not Collected** label, support URL, five showcase screenshots, and one 30-second app preview. Release is set to manual.

Completed listing settings include the public privacy-policy URL, $4.99 USD base price with all 175 storefronts selected, copyright `Copyright © 2026 Igor Chernakov`, and the supplied App Review contact. A valid Apple Distribution identity is still required to sign and upload. The current local build succeeds, but is only locally signed. After upload, select the processed build and leave the version in **Prepare for Submission**; release is set to manual.

## Upload flow

Choose the marketing version and next build number in App Store Connect. Set
`VERSION`, `BUILD_NUMBER`, and the numeric `APP_STORE_ID` in your shell. Build
with the matching Mac App Store profile, an installed distribution signing
identity, and an installed Mac App Store installer signing identity.

```sh
make store-package APP=diskmap VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
  PROFILE=/path/to/diskmap.provisionprofile
asc --profile corepunch builds upload --app "$APP_STORE_ID" \
  --pkg "build/store/diskmap/Diskmap-$VERSION.pkg" \
  --version "$VERSION" --build-number "$BUILD_NUMBER" --wait
```

Attach the processed build with `asc versions attach-build` using the macOS
version ID and the returned build ID. Keep release set to manual and leave
the version in **Prepare for Submission**.
