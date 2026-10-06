# Diskmap: what people ask about the Library folders

October 2026. A second research pass after the storage pass of September 2026
(`apps/diskmap/VISION.md`, `DISKMAP_STORAGE_SUGGESTIONS.md`). That pass
covered the big consumers of space. This one covers two questions it left
open: "what is this Library folder?" and "whose is it?". The sources were
Apple Support Communities, MacRumors forums, Apple Developer Forums, Stack
Exchange, Eclectic Light Company and Michael Tsai's blog. Claims were checked
on macOS 27 without root access and without Full Disk Access.

## Where the answers live

| Question | Answered by |
|---|---|
| What is this folder? (a fixed path) | `knowledge/Filesystem.lua`, shown on macOS Folders, searchable, and explained on the Folder page |
| What is this folder? (one folder per app) | `knowledge/Library.lua` `parents`, through `helpers/Explain.lua` |
| Whose is it? | `helpers/Leftovers.lua` `owner`, matched against `installedApplications` |
| Questions that are not about one folder | Storage Guide topics in `knowledge/Guide.lua` |

## "Precache"

macOS has no folder by that name. Two `find -iname '*precache*'` passes over
`/`, the Data volume, `~/Library`, `/Library`, `/private/var/db` and
`/private/var/folders` found nothing outside user projects. The string occurs
only as method names inside the shared cache, for example Mail's
`countOfItemsToPrecache`. When people say "precache" they mean one of these:

- **Staged macOS updates** in `/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate`.
  They are SIP-protected, and macOS purges them itself when space runs low
  ([Apple: Optimize storage](https://support.apple.com/guide/mac-help/optimize-storage-space-sysp4ee93ca4/mac),
  [Eclectic Light: how Tahoe updates](https://eclecticlight.co/2026/03/18/how-macos-26-tahoe-updates-4-download-preparation-and-installation/)).
- **Content Caching** in `/Library/Application Support/Apple/AssetCache/Data`.
  "Precache" is the name of the krypted script that fills that cache ahead of
  time ([krypted/precache](https://github.com/krypted/precache),
  [Apple: content caching from the command line](https://support.apple.com/guide/deployment/manage-content-caching-command-line-mac-depfaba5bc52/1/web/1.0)).
- **A folder actually named precache**, which some app or script made.
  Diskmap names its owner when it can.

## Folders people ask about most

Each one is now a location in the macOS Folders map, with an owner where one is known:

- `~/Library/Caches/com.apple.bird`: the iCloud Drive cache ([thread](https://forums.macrumors.com/threads/very-large-files-in-com-apple-bird.2240150/))
- `~/Library/Application Support/CloudDocs`: the iCloud Drive database ([Eclectic Light](https://eclecticlight.co/2024/03/18/how-icloud-drive-works-in-macos-sonoma/))
- `~/Library/Metadata/CoreSpotlight`: the index of content apps hand to Spotlight, which can run away ([OSXDaily](https://osxdaily.com/2025/04/30/clear-corespotlight-metadata-storage-mac/))
- `~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches`: photo analysis files that bloat after an update ([thread](https://discussions.apple.com/thread/255835917))
- `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`: copies of attachments you opened ([thread](https://discussions.apple.com/thread/255641800))
- `~/Library/Daemon Containers`: sandboxes of system services ([Eclectic Light](https://eclecticlight.co/2024/08/05/what-are-all-those-containers/))
- `~/Library/Biome` and `~/Library/Suggestions`: activity streams and Siri suggestions ([Eclectic Light](https://eclecticlight.co/2022/06/27/biome-isnt-about-biometrics-but-suggestions/))
- LaunchAgents, LaunchDaemons and PrivilegedHelperTools: left behind when an app is dragged to the Trash
- Preferences, Saved Application State, HTTPStorages and WebKit: small folders, one entry per app. The Applications page counts them as that app's data.

Topics covered in earlier passes are not repeated here: System Data,
snapshots, purgeable space, Spotlight, simulators, Docker, Adobe, Mail, and
Messages.

## Finding the owner of a Library folder

All checked without root access:

| Technique | Notes |
|---|---|
| Bundle identifier to app (`mdfind`, then `mdls kMDItemCFBundleIdentifier kMDItemDisplayName`) | One call covers every app. Diskmap already depended on Spotlight for this. |
| Code signature (`SecCodeCopySigningInformation`) | Gives the team ID and the `com.apple.security.application-groups` entitlement. For example, Podcasts declares `243LU875E5.groups.com.apple.podcasts`, exactly its Group Container. About 6 ms per bundle, so 788 bundles take 4.6 s. It runs off the main thread (`AppKit.codeSignatures`). |
| Container metadata (`.com.apple.containermanagerd.metadata.plist`, `MCMMetadataIdentifier`) | Needs Full Disk Access. Diskmap reads it only for containers named by a UUID. |
| `pkgutil --file-info` | Names the installer package of an item in `/Library`, for example GarageBand's sound content. Diskmap asks once per item, when it is selected. |
| `lsregister -dump` | Has the same facts, but the App Sandbox may block it, so Diskmap does not use it. |

A team ID can start with a digit: `243LU875E5` (Apple), `2DC432GLL2`
(OpenAI), `6N38VWS5BX` (Telegram). Leftover detection used to strip only
letter-led prefixes. As a result, such Group Containers were called "App not
installed" even when the app was installed.
