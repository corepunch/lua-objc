# Reproducing Diskmap's App Store promotional materials

The deliverables are five English Mac App Store screenshots and one app preview. The checked-in files are the exact media uploaded on October 4, 2026. The screenshots are under `en/screenshots/`; the preview is `en/previews/Diskmap-AppStore-Preview.mov`.

## The thinking behind the gallery

Lead with what someone with a full Mac wants to know: where the space went, what deserves a closer look, and how to make an informed cleanup decision. Each screenshot explains one benefit and shows the actual screen that supports it.

The reference galleries were [CleanMyMac](https://apps.apple.com/us/app/cleanmymac/id1339170533) and [DaisyDisk](https://apps.apple.com/us/app/daisydisk/id411643860). CleanMyMac places short benefit headlines above large app windows. DaisyDisk makes its storage map the visual centerpiece. Diskmap uses the same useful presentation principles with its own copy, interface and colors; no competitor artwork is reused. The observation is recorded in `en/market-research.md`.

| Order | Screen | Headline | Purpose |
| --- | --- | --- | --- |
| 1 | Storage Map | See what fills your Mac. | Establish the product at a glance with its colorful map and ranked categories. |
| 2 | Clean Up | Make space. Stay in control. | Explain rebuildable data and the review step before moving anything to Trash. |
| 3 | Large Files | Find the files worth a look. | Show size ranking, filters and last-used dates as decision aids. |
| 4 | File Types | Your storage, by kind. | Show the mix of videos, installers, archives and other kinds of files. |
| 5 | Developer tools | Less clutter. More building. | Show the footprint of Xcode, simulators, caches and projects. |

The first four images address general storage questions. The last adds a specific benefit for developers. Keep this order: the numbered filenames determine the upload order.

Copy should describe actions and information the product actually offers. Avoid guaranteed savings, automatic deletion claims or scan-speed promises. The gigabyte amounts are synthetic example data, not a promise of what another Mac can recover. Preserve the distinction between measured storage, estimated recoverable space and items to review.

## Visual approach

Every image is a 2880 × 1800 JPEG with no transparency. A large headline and a single supporting sentence sit above a complete native window. The same window scale and placement make the gallery feel consistent and keep the product interface readable.

- The app supplies every chart, symbol, row, value and control. Capture the real interface; do not redraw or invent product UI.
- Use the existing app icon from `Assets.xcassets/AppIcon.appiconset/icon_1024.png`.
- Storage Map, Large Files and Developer tools use dark appearance; Clean Up and File Types use light appearance. This demonstrates both appearances without spending a whole screenshot on them.
- The backgrounds use restrained purple, teal, blue and pale green gradients related to the app's colors. The window gets a soft shadow. Typography uses the Mac's system font.
- The compositor preserves the entire native window and its existing corners. Its 2560 × 1280 source is uniformly resized to 2520 × 1260 and placed at `(180, 500)`. No individual UI element is rearranged.

The copy, palettes and composition are defined in [scripts/diskmap-store-promos.py](../../../scripts/diskmap-store-promos.py). The pages and appearances are defined in [capture.lua](capture.lua). Paths in the commands below are relative to the repository root.

## Requirements

- macOS 26 or later and the project's normal build dependencies; see the root `README.md`.
- A working graphical Mac session with native window capture access. A restricted shell may need elevated execution to connect to WindowServer.
- Retina backing scale of 2 for the current capture recipe. A 1280 × 640 point window must produce a 2560 × 1280 pixel PNG; the compositor checks this explicitly.
- Python with Pillow and NumPy for the screenshot artboards.
- Apple's Swift toolchain and AVFoundation for the video export.
- The installed `asc` CLI and the existing `corepunch` Keychain profile for remote uploads.

You can use the bundled Codex Python runtime when it provides Pillow and NumPy. Alternatively, prepare an isolated environment:

```sh
python3 -m venv /tmp/diskmap-promo-env
/tmp/diskmap-promo-env/bin/python3 -m pip install Pillow numpy
```

The screenshot script uses `/System/Library/Fonts/SFNS.ttf`. Fonts, native controls and window appearance can change with macOS releases, so recapturing should reproduce the design, not necessarily identical JPEG bytes. The checked-in media preserve the exact uploaded edition.

## Generate the five screenshots

```sh
make
make diskmap-store-screenshots \
  DISKMAP_STORE_PYTHON=/tmp/diskmap-promo-env/bin/python3
```

The Make target launches Diskmap once with `--showcase`, captures all five pages, then composes and exports the artboards. Showcase uses deterministic synthetic data and does not scan personal files or change the user's saved choices. No Full Disk Access permission is needed for this capture workflow.

The resulting files are:

```text
apps/diskmap/store-assets/en/screenshots/
  01-map.jpg
  02-cleanup.jpg
  03-files.jpg
  04-kinds.jpg
  05-developer.jpg

build/diskmap-store/
  map.png           map.layout.xml
  cleanup.png       cleanup.layout.xml
  files.png         files.layout.xml
  kinds.png         kinds.layout.xml
  developer.png     developer.layout.xml
  contact-sheet.jpg
```

The compositor replaces the JPEGs in the gallery directory with exactly these five files. Raw captures, native layout dumps and the contact sheet stay in ignored `build/`.

If only marketing copy or the artboard colors changed, recompose from existing captures:

```sh
/tmp/diskmap-promo-env/bin/python3 scripts/diskmap-store-promos.py
```

If the app interface or showcase data changed, run the full Make target again. Keep the UI captures and copy in agreement.

## Generate the app preview

The source is the existing `build/Diskmap-Showreel.mov`. To recreate that source:

```sh
make diskmap-reel
```

This renders the 34-second showreel from the storyboard, native app captures and synthesized soundtrack under `reels/diskmap/`. See `reels/diskmap/README.md` for its scenes and rendering workflow. After an interface change, run `make diskmap-reel-captures` before rendering so the reel uses fresh UI captures.

Create the store-ready edition:

```sh
make diskmap-store-preview
```

`scripts/diskmap-store-preview.swift` uses native AVFoundation to retain every scene while compressing the timeline to fit the App Store's limit. Audio pitch is preserved with the spectral time-pitch algorithm. Export uses the 1920 × 1080 preset and an explicit 30 fps video composition.

The uploaded edition is 29.97 seconds, 1920 × 1080, progressive H.264 High Level 4.0 with stereo AAC audio, about 33 MB. The export goes directly to `apps/diskmap/store-assets/en/previews/Diskmap-AppStore-Preview.mov`. The full 34-second source stays in `build/`.

Apple's [app preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/) require a 15–30 second preview, at most 500 MB, supported video/audio encoding, and landscape orientation for Mac. Verify current requirements before changing the export settings. A successful local export is separate from Apple's delivery status.

## Quality checks

```sh
./lua-objc --test tests/diskmap_store_assets.test.lua
asc screenshots validate \
  --path apps/diskmap/store-assets/en/screenshots \
  --device-type DESKTOP --output json
git diff --check
```

The headless test checks the five filenames, order, JPEG headers and exact 2880 × 1800 dimensions. CLI validation checks that each screenshot is suitable for the Mac display type.

Inspect the contact sheet and each full-size JPEG. Check headline and subtitle fit, readable interface text, the intended page and appearance, intact window corners, native scroll boundaries and absence of personal data. Consult the corresponding `.layout.xml` when something looks clipped or misaligned; fix the actual app/framework if its UI is wrong.

Play the exported video through to the end. Check the opening, transitions, readable text, complete closing scene, sound, duration and resolution. The original upload of the 34-second source failed processing; do not upload that source as the store preview.

## Upload with asc

The existing destination is app `6816896153` (`org.luaobjc.diskmap`), macOS version `1.0`, English locale `en-US`. Its version localization ID is `2935b7eb-1995-4d58-9574-5757a471087b`. These IDs refer to this version; discover the localization again for a future version.

Check authentication and the current destination:

```sh
asc --profile corepunch auth status --validate
asc --profile corepunch versions list \
  --app 6816896153 --platform MAC_OS --output json
asc --profile corepunch localizations list \
  --app 6816896153 --platform MAC_OS --output json
```

Discover command changes with `asc search "screenshots upload" --output json`, `asc search "previews upload" --output json`, and the relevant command's `--help`.

Preview replacements first by using `--replace --dry-run`. The actual uploads below replace the target localization's Mac media sets, so they use `--replace --confirm`:

```sh
asc --profile corepunch screenshots upload \
  --version-localization 2935b7eb-1995-4d58-9574-5757a471087b \
  --path apps/diskmap/store-assets/en/screenshots \
  --device-type DESKTOP --replace --confirm --output json

asc --profile corepunch video-previews upload \
  --version-localization 2935b7eb-1995-4d58-9574-5757a471087b \
  --path apps/diskmap/store-assets/en/previews/Diskmap-AppStore-Preview.mov \
  --device-type DESKTOP --replace --confirm --output json
```

Set the video poster after upload, using the new preview asset ID returned by asc:

```sh
asc --profile corepunch video-previews set-poster-frame \
  --id NEW_PREVIEW_ASSET_ID --time-code 00:00:08:09 --output json
```

At 30 fps this selects 8.3 seconds, showing the storage map. Use the frame-based timecode: Apple rejected the millisecond form during this upload. A subsequent read may be needed before the changed timecode appears.

Verify the remote results independently:

```sh
asc --profile corepunch screenshots list \
  --version-localization 2935b7eb-1995-4d58-9574-5757a471087b --output json
asc --profile corepunch video-previews list \
  --version-localization 2935b7eb-1995-4d58-9574-5757a471087b --output json
```

Expect five screenshots in filename order and one preview, each with delivery state `COMPLETE`. Compare `sourceFileChecksum` with the MD5 of the corresponding local file; also check screenshot dimensions, video byte count and poster timecode. If Apple reports a processing failure, inspect and correct the media before uploading again. Do not treat a successful transfer alone as verification.

Save upload and verification reports under `build/diskmap-store/` and update `en/metadata.md` with the resulting media IDs. Keep credentials in Keychain; never put private keys or tokens into this guide or the repository. Media uploads do not submit or release the app.

## What belongs in Git

Commit the five final JPEGs, the final preview MOV, the capture plan, both generation scripts, the Makefile targets, the gallery test, and the listing/research documentation. Keep intermediate captures, layout dumps, export logs, Swift module caches and the full showreel in ignored `build/`. They can be regenerated from the sources above.
