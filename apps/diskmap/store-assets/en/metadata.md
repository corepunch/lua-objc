# App Store Connect listing (English, macOS)

## Product page

- **Name:** Diskmap - Storage Optimization (30 characters; accepted by App Store Connect)
- **Subtitle:** See what fills your Mac
- **Promotional text:** Make sense of Mac storage. Explore a visual map, find large files and developer data, and review suggested cleanup before anything moves.
- **Primary category:** Utilities
- **Support URL:** https://github.com/corepunch/lua-objc/issues
- **Privacy policy URL:** https://github.com/corepunch/lua-objc/blob/main/apps/diskmap/PRIVACY.md
- **Marketing URL:** Optional; none supplied.

## Description

See what is using storage on your Mac. Diskmap measures your startup disk and turns the results into a clear overview, a folder map, and useful categories.

Explore large files, applications, caches, Xcode data, simulators, projects, backups, snapshots, and mounted disks. See when files were last used, compare rebuildable data with items that deserve a closer look, and follow practical cleanup recommendations.

When you choose to clean up, Diskmap shows the selected items and checks them again before moving them to the Trash. It does not silently delete files. Folder Map also lets you inspect a folder or another disk directly.

Diskmap works best with Full Disk Access. You grant that permission yourself in macOS System Settings. Without it, Diskmap continues with the locations macOS allows it to read and identifies areas it could not measure.

Designed for macOS 26 and later.

## Keywords (87 characters)

disk,storage,space,cleanup,large files,drive analyzer,folder map,xcode,cache,duplicates

## App preview and screenshots

- **Reproduction and design rationale:** [Promotional materials guide](../README.md).
- **App preview:** `apps/diskmap/store-assets/en/previews/Diskmap-AppStore-Preview.mov` (29.97 seconds, 1920 × 1080, 30 fps, H.264 High Level 4.0, stereo AAC; Mac landscape preview). `make diskmap-store-preview` exports the complete 34-second `build/Diskmap-Showreel.mov` at a slightly faster pace, preserving audio pitch, to meet Apple's 30-second limit.
- **Screenshots:** `screenshots/01-map.jpg`, `02-cleanup.jpg`, `03-files.jpg`, `04-kinds.jpg`, and `05-developer.jpg` (2880 × 1800 JPEG, no transparency). Each artboard pairs benefit copy with a complete native window captured from the showcase disk. They cover storage visualization, guided cleanup, large files and last use, file types, and developer storage.
- **Regenerate:** `make diskmap-store-screenshots DISKMAP_STORE_PYTHON=/path/to/python3` with Pillow and NumPy installed. Raw captures, native layout dumps, contact sheet, and upload verification reports live in `build/diskmap-store/`.
- Screenshots use the Diskmap showcase profile and synthetic example content.
- **App icon:** `../../Assets.xcassets/AppIcon.appiconset/` (1024 × 1024 source plus macOS sizes).

### Media uploaded October 4, 2026

Uploaded through `asc --profile corepunch` to app `6816896153`, macOS version `1.0`, English (`en-US`) localization `2935b7eb-1995-4d58-9574-5757a471087b`. The five new screenshots replace the previous six plain window captures. The compliant preview replaces the failed 34-second upload. A subsequent read verified every asset's filename, checksum and `COMPLETE` delivery status, plus screenshot order and dimensions.

Screenshot set: `5ddf5bd4-617d-476c-8761-277837eaa209`. Preview set: `5c50d28a-7321-41ef-9ef8-14665535a7fb`; preview asset: `36400019-6519-8499-8131-66771b800c8a`, with storage-map poster timecode `00:00:08:09`. Verification reports are in `build/diskmap-store/screenshots-verified.json` and `preview-verified.json`. Version 1.0 remains `PREPARE_FOR_SUBMISSION`.

## Current App Store Connect state

- Age rating: 4+, based on all feature/content answers being No/None.
- Content rights: No third-party content.
- App Privacy: **Data Not Collected**, published.
- Price: $4.99 USD base price; all 175 storefronts selected.
- Copyright: Copyright © 2026 Igor Chernakov.
- App Review contact: Igor Chernakov; contact details supplied and saved in App Store Connect.
- Release: manual.
- Build: Release compiles locally; it still needs an Apple Distribution signing identity, upload, processing, and selection on Version 1.0.
- Reviewer notes explain optional Full Disk Access and that preview data is synthetic. Do not submit until the signed sandboxed app has been exercised with and without Full Disk Access.
