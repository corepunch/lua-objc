# Diskmap storage suggestions research

Reviewed September 21, 2026. Forum posts identify recurring problems; vendor
instructions establish what the app recommends. Claims in forum posts are not
executable instructions or authority to delete a user's data. The shared ChatGPT
conversation supplied for the task could not be retrieved; the supplied image was
used as the visual reference.

## Recurring reports

- [Simulator removal confusion, r/Xcode](https://www.reddit.com/r/Xcode/comments/1du8m6s/how_do_i_remove_old_xcode_simulators_still_on_my/)
- [Docker.raw size confusion, r/docker](https://www.reddit.com/r/docker/comments/u7qke3)
- [System Data and backup confusion, r/mac](https://www.reddit.com/r/mac/comments/1icznf9)
- [System Data and application logs, r/mac](https://www.reddit.com/r/mac/comments/16zcs2x)

These reports motivate separating caches, backups, simulator data and sparse
virtual disks instead of treating “System Data” as one removable category.

## Primary references and product decisions

| Source | Decision |
| --- | --- |
| [Apple: Free up storage](https://support.apple.com/en-nz/102624) | System Data is a broad category; recommend specific measured locations. |
| [Apple: Local Time Machine snapshots](https://support.apple.com/en-ie/102154) | Explain automatic management; never promise reclaimable bytes or remove restore points. |
| [Apple: Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components) | Manage simulator runtimes in Xcode Components; do not delete mounted runtime assets. |
| [Apple: Getting the Most Out of Simulator](https://devstreaming-cdn.apple.com/videos/wwdc/2019/418o9bbtoe880sauh/418/418_getting_the_most_out_of_simulator.pdf) | Device deletion loses installed apps, settings and test data. |
| [Docker: Backup and restore](https://docs.docker.com/desktop/settings-and-maintenance/backup-and-restore/) | Docker.raw is a data store; do not classify it as disposable cache. |
| [Docker: Images view](https://docs.docker.com/desktop/use-desktop/images/) | Direct users to Docker's own review/cleanup controls. |
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
