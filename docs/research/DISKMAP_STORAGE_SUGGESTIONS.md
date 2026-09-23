# Diskmap storage suggestions research

Reviewed September 23, 2026. Forum posts identify recurring problems and
self-reported outcomes; vendor instructions establish what the app recommends.
Forum claims are anecdotal, are not guaranteed reclaim amounts, and are not
executable instructions or authority to delete a user's data. The shared ChatGPT
conversation supplied for the original task could not be retrieved; its supplied
image was used as the visual reference.

## Recurring reports

- [Simulator removal confusion, r/Xcode](https://www.reddit.com/r/Xcode/comments/1du8m6s/how_do_i_remove_old_xcode_simulators_still_on_my/)
- [Docker.raw size confusion, r/docker](https://www.reddit.com/r/docker/comments/u7qke3)
- [System Data and backup confusion, r/mac](https://www.reddit.com/r/mac/comments/1icznf9)
- [System Data and application logs, r/mac](https://www.reddit.com/r/mac/comments/16zcs2x)

These reports motivate separating caches, backups, simulator data and sparse
virtual disks instead of treating “System Data” as one removable category.

## Community reports with reported outcomes

These threads were checked for what the poster or a follow-up commenter actually
found or said worked. Sizes below are individual reports, not expected savings.

| Report and outcome | What Diskmap should learn |
| --- | --- |
| In [r/mac's storage guide](https://www.reddit.com/r/mac/comments/1c3ldoi/wheres_my_disk_space_what_is_taking_up_all_the/), users reported finding 150 GB of After Effects cache, old Adobe files plus screen recordings totaling about 100 GB, and a five-hour recording of 14 GB. One user said inspecting folder sizes and removing files they recognized restored space. | The label “System Data” is too broad to guide cleanup. Help users identify a named owner and measured path; large screen recordings still need individual review. Do not infer that an unknown large file is disposable. |
| In [r/AfterEffects](https://www.reddit.com/r/AfterEffects/comments/ixvkw6/huge_after_effects_cache_folder_is_it_safe_to/), commenters report default disk-cache folders from 100 GB to more than 700 GB; one said following the thread's advice returned their available space from about 40 GB to over 250 GB. An [Adobe Community](https://community.adobe.com/questions-529/after-effects-stops-responding-when-opening-preferences-and-purging-cache-55899) reply places the default cache under the user's `Library/Caches/Adobe` tree. Separately, [r/applehelp](https://www.reddit.com/r/applehelp/comments/makyuo) and [r/editors](https://www.reddit.com/r/editors/comments/jlg00c) report oversized shared Adobe media caches, including older-version residue. | Add two default, review-only locations: Adobe application caches under `~/Library/Caches/Adobe` and shared `Media Cache Files` under `~/Library/Application Support/Adobe/Common`. Direct users to Adobe's own cache controls; customized locations are not measured, and one After Effects version's purge does not clear another version's cache. |
| A [2026 r/mac storage thread](https://www.reddit.com/r/mac/comments/1w2wp8x/system_data_381_gb_what_is_it_can_i_delete_it_is/) includes a user report of a 62 GB Apple Mail logging file, with logging disabled before deleting it. An [Apple Support Community thread](https://discussions.apple.com/thread/251036711) describes Mail connection logs growing to 700 GB and recommends turning off Connection Doctor logging. | Add the exact Mail connection-log folder as a separate review-only resource. Tell users to switch logging off first and use Mail's Show Logs control. Do not conflate these diagnostics with saved messages or local mailboxes. |
| In [r/Xcode](https://www.reddit.com/r/Xcode/comments/1ry2tnx/xcode_was_quietly_using_60gb_on_my_mac_this_is/), a user listed 14 GB DerivedData, 28 GB of simulator runtimes, 9 GB of archives, and 6 GB device support. Replies report clearing DerivedData and removing runtimes they no longer test; one user said removing iOS and watchOS runtimes returned more free space than their listed size. The post author disclosed making a cleanup app, so its own recommendations are not treated as independent evidence. | Keep DerivedData review separate from archives and simulator device data. Explain that builds recreate DerivedData, remove runtimes through Xcode for OS versions the user no longer needs, and preserve device data that may contain test state. APFS sharing means measured and reclaimed sizes may differ. |
| In [r/mac](https://www.reddit.com/r/mac/comments/1bj2qqx/), a user tracing a sudden storage drop found a large iPhone backup and an 8 GB iOS restore image; they reported about 30 GB returning after disconnecting the phone and identified the remaining files. | Direct users to Finder's Manage Backups for named, dated backups. Treat software update images as a separate, identified download; do not recommend deleting arbitrary files from hidden folders. |
| In [r/mac](https://www.reddit.com/r/mac/comments/1f6posc/), a follow-up said clearing Adobe caches helped but left roughly 400 GB unexplained; a disk inventory then revealed an unknown 430 GB video, which they deleted and reported restored the expected space. A separate user in a [Docker discussion](https://www.reddit.com/r/mac/comments/ynv4d0/system_data_taking_up_all_my_storage_how_do_i_fix/) reported finding and clearing 100 GB of Docker logs. | Large videos and logs can be the actual outlier. Keep the advice tied to an identified file or Docker-owned data; never advise deleting a whole unknown file, virtual disk, or Docker store based on size alone. |

## Follow-up investigations

### Screen recordings and personal video

Apple's Screenshot controls allow a user-selected save location, and the
floating thumbnail can be dragged elsewhere. QuickTime Player also records the
screen. A movie extension, filename, creation date, or location therefore does
not establish that a file is a screen recording or identify its owner;
third-party recorders and edited or moved files further weaken those signals.
Apple's public file-metadata documentation defines general video attributes,
but does not document a stable attribute that identifies saved screen
recordings across recording apps.

**Decision:** Do not add a screen-recording category or infer recording status
from names, extensions, or size. Leave identified videos in their general
measured location and require the user to identify each file in Finder; do not
claim every custom or external destination is scanned. The known Movies library
remains excluded by default until the user opts into media measurement;
Screenshot's save location may be a different folder.

### Docker container logs

Docker supports `docker inspect` fields for a container's logging driver and
log path, and `docker logs` reads output when the configured driver supports
reading. Together with Docker's documentation that Docker Desktop runs its
engine in a Linux VM, this implies the reported log path is daemon-side rather
than a stable macOS file path. The disk image can also be moved in Docker
Desktop settings. Logging drivers may rotate files, send data to remote
services, or disable local reads. Docker Desktop's Resources settings show the
disk image's configured location and actual usage; the documented Logs view
shows log entries but not per-container allocated bytes.

**Decision:** Keep one aggregate Docker Desktop resource at the documented
default app-container location. Explain that a custom disk-image location may
not be measured and direct owners to Docker Desktop's Resources settings and
Logs view. Do not add a per-container log label or derive its size from log
output. Prune only identified unused data in Docker; preserve volumes and the
virtual disk unless the owner intentionally manages them there.

### iOS restore images

Apple documents updating a connected device through Finder and using a chosen
`.ipsw` file with Apple Configurator. The reviewed Apple guidance does not
document a stable Finder-downloaded IPSW path or an owner-managed Finder flow to
inspect and remove cached restore images. The `.ipsw` file used with
Configurator is a user-selected file and may live wherever its owner saved it.
Finder's supported **General > Manage Backups** workflow applies to device
backups, not restore images.

**Decision:** Keep restore images distinct from named Finder-managed backups,
but do not add an IPSW path or cleanup recommendation. Any such file remains in
the general measured inventory under its actual containing location; do not
recommend deleting a guessed hidden file.

The code changes from this review are in `apps/diskmap/catalog/SystemData.lua`
and `apps/diskmap/knowledge/CleanupRules.lua`: Adobe application caches,
shared Adobe media cache, and Mail connection logs have separate measured
locations and owner-specific guidance; backup, Xcode build-data, and Docker
advice now reflects these reports. The three follow-up investigations above
did not establish reliable new labels for recordings, Docker logs, or IPSW
images, so those stay in the existing general inventory.

## Owner instructions used for new guidance

| Source | Decision |
| --- | --- |
| [Adobe: clear Premiere media cache](https://helpx.adobe.com/premiere/desktop/troubleshooting/media-issues/clear-media-cache-using-preferences.html) | Clear through Premiere settings; needed cache files are recreated. |
| [Adobe: manage Premiere media cache](https://helpx.adobe.com/premiere/desktop/troubleshooting/media-issues/manage-media-cache.html) | The default macOS cache is under `~/Library/Application Support/Adobe/Common`; users can customize it. |
| [Adobe: After Effects memory and storage](https://helpx.adobe.com/after-effects/desktop/memory-storage-performance/memory-and-storage/memory-storage1.html) | Manage disk and media caches in After Effects settings. Check source-media volumes before cleaning cache database entries. |
| [Adobe Community: After Effects cache location](https://community.adobe.com/questions-529/after-effects-stops-responding-when-opening-preferences-and-purging-cache-55899) | A macOS troubleshooting reply identifies the default cache root as `~/Library/Caches/Adobe`; After Effects settings allow a custom folder. |
| [Ask Different: large Apple Mail logs](https://apple.stackexchange.com/questions/223390/huge-apple-mail-logs-connection-logging-enabled) | Mail's Window > Connection Doctor checkbox enables log generation; disable logging before reviewing those files. |
| [Apple Support Community: Mail IMAP logs](https://discussions.apple.com/thread/251036711) | Reports of extreme log growth reinforce a separate logs resource; the message store is not a cleanup target. |

## Primary references and product decisions

| Source | Decision |
| --- | --- |
| [Apple: Free up storage](https://support.apple.com/en-nz/102624) | System Data is a broad category; recommend specific measured locations. |
| [Apple: Local Time Machine snapshots](https://support.apple.com/en-ie/102154) | Explain automatic management; never promise reclaimable bytes or remove restore points. |
| [Apple: take screenshots or screen recordings on Mac](https://support.apple.com/en-hk/guide/mac-help/-mh26782/mac) | Recording destinations are user-configurable; a Desktop-only inventory would miss files saved elsewhere. |
| [Apple: update a device with Finder](https://support.apple.com/en-us/HT212185) | Finder's supported update flow acts on a connected device; the article provides no persistent IPSW cache path or file cleanup workflow. |
| [Apple: update devices with Apple Configurator](https://support.apple.com/en-gb/guide/apple-configurator-mac/cad789a3f0bd/mac) | Configurator accepts a user-selected `.ipsw` file; this does not establish a Finder cache path. |
| [Apple: Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components) | Manage simulator runtimes in Xcode Components; do not delete mounted runtime assets. |
| [Apple: Getting the Most Out of Simulator](https://devstreaming-cdn.apple.com/videos/wwdc/2019/418o9bbtoe880sauh/418/418_getting_the_most_out_of_simulator.pdf) | Device deletion loses installed apps, settings and test data. |
| [Docker: Backup and restore](https://docs.docker.com/desktop/settings-and-maintenance/backup-and-restore/) | Docker.raw is a data store; do not classify it as disposable cache. |
| [Docker: Images view](https://docs.docker.com/desktop/use-desktop/images/) | Direct users to Docker's own review/cleanup controls. |
| [Docker Desktop for Mac FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) | The disk image location and actual usage appear in Resources > Advanced; owners can move the image, so its default path is not universal. |
| [Docker: configure logging drivers](https://docs.docker.com/engine/logging/configure/) and [inspect](https://docs.docker.com/reference/cli/docker/inspect/) | Log drivers differ; inspect exposes daemon log paths and drivers, not a universal host-side allocated-byte measurement. |
| [Docker Desktop Logs view](https://docs.docker.com/desktop/use-desktop/logs/) | Review log output in Docker Desktop; the Logs view does not report per-container disk allocation. |
| [npm cache](https://docs.npmjs.com/cli/v7/commands/npm-cache/) | Cache contains package downloads; removing it affects future download requirements. |
| [pip cache](https://pip.pypa.io/en/stable/cli/pip_cache/) | Cached wheels/downloads are separate from installed environments. |
| [Homebrew manual](https://docs.brew.sh/Manpage) | Cached downloads are distinct from installed packages; account for future downloads. |

## Permission model

[DaisyDisk documents](https://web.daisydiskapp.com/guide/4/en/FinderMismatch)
that first scans can request folder permissions and macOS remembers the choice.
Its [Full Disk Access guide](https://web.daisydiskapp.com/guide/full-disk-access)
explains comprehensive access. Folder-size computation needs directory enumeration
and metadata access even without opening contents; Apple's
[Documents permission description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdocumentsfolderusagedescription)
and [sandbox access guide](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
describe the consent boundaries.

Diskmap defaults to targeted checks, leaves protected suggestions unmeasured, and
uses an explicit native folder picker for broader scans. Declining access does not
block the rest of the product. No Full Disk Access prompt is shown on startup.
