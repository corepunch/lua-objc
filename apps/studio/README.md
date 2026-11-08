# Lua Studio

A standalone Lua app development workspace: an interactive UIKit preview of the
project, an OpenRouter coding agent, and an editable local project. The device
runs Lua and etlua directly; ordinary app changes need no native build or Mac
packager.

On iPad the workspace is three landscape columns: the phone-sized preview, the
agent and the code. Both landscape directions are supported; portrait and
portrait-upside-down are excluded from the bundle and the live window. Keep this
requirement in [AGENTS.md](AGENTS.md) and verify with landscape screenshots.

On iPhone (portrait) the project itself fills the screen, running as it will
ship, and Studio is the capsule in its tab bar, where Music keeps its player.
The capsule says what the agent last did; a tap unfolds the conversation as a
sheet with the project still live beneath, and Code pushes the editor over the
transcript. The project menu in the sheet gathers the project, Run, Undo, Commit,
Share, GitHub, New Project, Delete Project and Settings. Run it in the iPhone
Simulator with the streaming host:

```sh
make ios-run PROJECT=apps/studio
```

## Install

```sh
make ipad-deploy             # auto-select exactly one connected iPad, sign, install, launch
make list-devices
make ipad-deploy IPAD_DEVICE=<identifier>  # select among multiple iPads
make ipad-run                # build and launch an available iPad simulator
make ipad                    # physical-device bundle only
make ipad-simulator          # simulator bundle only
```

Requires Xcode with the iOS 26.5 SDK and an iPad running iPadOS 26.5 or later.
Device signing uses a matching installed Apple development identity and an
unexpired provisioning profile that includes the iPad. `TEAM`, `PROFILE`, and
`BUNDLE_ID` can override selection. The default bundle ID is `org.luaobjc.studio`.
The deployment flow follows `mapview/ui`'s direct SDK build and installed-profile
signing approach. Discovery consumes `devicectl` JSON and filters for iPads;
failed signing/install steps stop the command.

## Use

Choose an existing project in the preview's project menu, or create one with
New Project or Templates. Blank App starts with a Lapis model, a controller,
and etlua layouts/pages; Habit Tracker provides a working example. Projects
have independent source, local app data, Git repositories, undo, and conversations.
Delete Project in the project menu asks for confirmation, then removes that
project's source, drafts, local app data and Git history from the iPad. Published
GitHub repositories remain intact. Deleting the last project shows New Project;
deleted bundled examples do not return on relaunch.

Code in the rail opens an editable, syntax-highlighted source view. Select a
file, hide the tree for more room, then Save and Run. Syntax errors preserve the
editable draft and last working preview. Undo discards a draft or restores the
previous saved source. Commit records saved source in the project's Git history.

Settings accepts your OpenRouter API key and provider/model ID. The key stays in
the device Keychain. Settings uses a native navigation sheet and system Done item;
Delete Project uses the system confirmation alert with native Cancel and Delete
actions. The optional assistant starts with `openrouter/free` and
requires a user-supplied key; provider charges may apply for other models. Before
enabling it, Settings explains that messages, selected attachments, and source
requested by the agent are sent to OpenRouter and its model provider. Send starts
a real tool loop, Stop cancels it, and changed-file cards describe actual edits.
The agent can read a bundled reference for the actual control, model and template APIs.
Its `testAction` tool runs a named controller action in the current preview and returns
bounded plain data, so it can check input, creation, filters and toggles after rendering.
These actions change the running app, including its local data when it saves. Action
tests use the same execution budget as initial rendering. A turn is limited to 24
provider requests. Truncated, empty and failed provider responses end with a visible
error; incomplete tool batches are rejected before edits. Saved-file cards distinguish
a working preview from a failed reload that kept the previous preview. Provider
failures retain completed conversation context for a manual retry and explain
when to check the key, wait for a rate limit, or choose another model. Studio
does not automatically retry or switch to a paid model.
New Conversation clears the in-memory conversation. Dictation uses Apple's Speech
service on demand; the attachment button accepts up to four UTF-8 text files,
128 KB each, as context. Neither sends anything until Send is pressed.

Share and Export use the native share sheet to save a source ZIP. The ZIP includes
source, the manifest, a build README and app icon; it excludes runtime data, Git, settings and
credentials. Export rewrites the preview namespace to the real `apps/<project>` folder so
the source can run in a lua-objc checkout on Mac. Signing a standalone iPhone app requires a Mac and Apple signing
tools. There is no in-app cloud build or App Store deployment service.

Run/reload, preview appearance, fit/75% zoom, preview focus, project icons,
Templates, Examples and Settings are functional. Plugins lists the host's included
capabilities; adding a new native plugin requires rebuilding the host.

## Headless tests

```sh
make studio-test
```

This builds a small interpreter from the repository's vendored Lua 5.4 sources,
then runs the Studio domain, agent, transport, project creation, source editing,
save/rollback, undo, dictation, attachments, export and template-action tests.
It needs no window, simulator, API key, network, Ruby or downloaded dependencies.
It also avoids the system/Homebrew Lua version. Subsequent runs take a fraction
of a second. Fastlane's `studio_check` includes this target.

For the real UIKit controls and screenshot checks:

```sh
make studio-smoke
# Reuse an explicitly selected, disposable iPad simulator:
make studio-smoke STUDIO_SMOKE_DEVICE=<simulator-UDID>
# Limit scenarios while debugging:
python3 scripts/ipad/studio_smoke.py --scenarios code,long --layouts standard
python3 scripts/ipad/studio_smoke.py --scenarios code,long,settings --appearance dark
# Opt-in live upload to the existing private verification repository. Uses the
# narrow GitHub review token from STUDIO_REVIEW_GITHUB_TOKEN; never reads Keychain.
python3 scripts/ipad/studio_smoke.py --device <simulator-UDID> \
  --identifier org.luaobjc.studio.workflowcheck \
  --runtime-root build/studio-verification/runtime \
  --layouts standard --scenarios github-prepare
python3 scripts/ipad/studio_github_verify.py --device <simulator-UDID> \
  --repository corepunch/lua-studio-git-verification-20261106
```

The optional smoke test requires Xcode and an installed iOS runtime. It uses local
Apple tools, creates an approximately 2 GB temporary iPad simulator by default,
and removes it even on failure. A device supplied with `--device` is preserved.
Simulator.app need not be open. The snapshot harness proposes landscape standard
(1210 × 834), wide (1366 × 834), and small (1024 × 768) window sizes directly.
A separate `org.luaobjc.studio.smoke` app and build folder use
`test/studio-smoke/` and a deterministic provider; no API key or network request is
needed. Native editor events, project creation/switching, generated edits,
failed-preview recovery, agent-driven action tests and preview reloads are exercised. The real Files picker and ZIP share sheet are
presented; the exported ZIP is inspected. Screenshots, native geometry snapshots,
and `results.json` are written under `build/studio-smoke/`; a failure includes a
screenshot and startup log. The script checks important control frames for clipping
at both window sizes and verifies native 2× screenshot resolution. It does not
automate microphone permission or record audio.
Lifecycle scenarios use separate app launches to verify creation, native editing,
Keychain and model settings, icon selection, Git history, invalid-save recovery,
reopening, deletion cancellation, the empty catalog, and creation afterward.
Use `--identifier` and `--runtime-root` to isolate simultaneous test runs.

Native AppKit regression tests for the shared template and editor contracts also
run through `make test`. On this machine the broad suite has unrelated failures
from Homebrew Lua 5.5, unavailable Metal rendering, and restricted system services;
the Studio-only target remains independent of those dependencies.

## App Store preparation with Fastlane

The App Store draft is [Lua Studio: iPhone App Builder](https://appstoreconnect.apple.com/apps/6831704812/distribution),
app ID `6831704812`, bundle ID `org.luaobjc.studio`. The installed app remains
**Lua Studio**. Version `1.0.0` is iPad-only, free, and set to manual release.

Run these commands from the repository root with the existing Fastlane installation:

```sh
fastlane ios studio_check
fastlane ios studio_auth_check  # read-only credential validation
fastlane ios studio_build build_number:4
fastlane ios studio_build build_number:4 profile:build/signing/studio/AppStore.mobileprovision
fastlane ios studio_metadata
fastlane ios studio_pricing
fastlane ios studio_screenshots
fastlane ios studio_upload
fastlane ios studio_readiness
# Run only when submission is authorized:
fastlane ios studio_submit
```

`studio_metadata` uses Fastlane **deliver**; `studio_upload` uses **pilot**, waits
for processing, then attaches the valid build to the App Store draft.
`studio_readiness` uses **precheck**. Preparation lanes do not submit or release
the app. `studio_submit` checks readiness and explicitly submits the verified
build to App Review, retaining manual release. `studio_prepare` runs the offline checks, metadata upload, free-price
verification, and readiness checks in order. It stops with an error while the
recorded product blockers remain.

The native build continues to use the repository Makefiles; there is no Xcode
project for Fastlane gym. The signed IPA is
`build/release/studio/LuaStudio-1.0.0.ipa`, with its dSYM under
`build/release/studio/symbols/`. Fastlane text metadata, review notes, and original
iPad screenshots live in `store-assets/`. The existing runtime rocket is supplied
through an AppIcon asset catalog. `PrivacyInfo.xcprivacy` is copied to the app
bundle root, outside the Lua workspace.

Fastlane reads its Apple API credential exclusively from environment variables:
`APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY_KEY`, and `APP_STORE_CONNECT_API_KEY_IS_KEY_CONTENT_BASE64`.
The local protected file `~/.config/lua-objc/fastlane.env` is loaded by new shells
and linked as the ignored `fastlane/.env`, which Fastlane loads automatically.
It also provides `STUDIO_REVIEW_GITHUB_TOKEN` and `STUDIO_REVIEW_OPENROUTER_KEY`.
No lane performs a Keychain lookup or prompts for an API credential. App Review
contact information is held in the ignored
`build/studio-submission/review-contact-source.json`; its shape is
`{"data":{"attributes":{"contactFirstName":"…","contactLastName":"…","contactPhone":"…","contactEmail":"…"}}}`.
The current contact was reused from the owner's existing App Store app.

The distribution private key and profile are preserved locally in
`build/signing/studio/` and the signing identity is installed in the login
Keychain. Keep an encrypted backup of this signing material before removing
build outputs. For CI, use GitHub Actions secrets for signing assets and the API
key. Never commit their contents. The release catalog names the Studio-specific
secrets `STUDIO_APPSTORE_CERTIFICATE_P12`, `STUDIO_APPSTORE_CERTIFICATE_PASSWORD`,
and `STUDIO_APPSTORE_PROFILE`, plus the variable `STUDIO_APPSTORE_ID`. The shared
release workflow reads the certificate names per app so Studio's new identity
does not replace another app's signing identity. These CI secrets are not
configured by the local Fastlane preparation.

### Release validation

Version **1.0.0**, build **4**, was resubmitted through Fastlane with landscape
screenshots on November 7, 2026. Apple confirmed **Waiting for Review** and
release remains manual. The local submission receipt is
`build/studio-submission/submission.json`.

The four App Store screenshots are native **2752 × 2064 landscape** captures:
the source workspace in light and dark appearances, an assistant edit with its
diff, and GitHub setup. `make studio-test` checks their PNG dimensions before
upload; `studio_readiness` checks the uploaded files against their local hashes.

Build **4** includes the verified libgit2 GitHub account, repository and
destination-branch publishing flow. The real assistant has passed an
edit/save/preview cycle with `openrouter/free`; the headless suite verifies that
requests omit the unsupported `parallel_tool_calls` parameter.

The revised listing, four current iPad screenshots, privacy policy and App Store
privacy answers have been published. The privacy answers declare Other User
Content, Name, Email Address and User ID linked to the account, and Audio Data
not linked, all for app functionality without tracking. Fastlane's privacy action requires an Apple web
session; this update used the existing signed-in browser because Fastlane had no
saved web session.

Private review access is supplied to Fastlane through
`STUDIO_REVIEW_OPENROUTER_KEY` and `STUDIO_REVIEW_GITHUB_TOKEN`, with the owner's
explicit approval. Desktop GitHub verification also reads
`STUDIO_REVIEW_GITHUB_TOKEN` from the environment, with no Keychain fallback or
password dialog. Set it in the environment before running the helper; never
commit its value. The restricted review token expires December 6, 2026, and
grants Contents read/write access only to the private verification repository.
Both credentials are appended to Apple's private review notes in memory,
never committed to the repository.
Keep command output redacted whenever supplying it. The uncommitted evidence in
`build/studio-submission/completion.json` contains publication hashes and boolean
checks only. `studio_readiness` compares the attached build and screenshot
checksums with the local package, checks the listing and manual-release setting,
and runs precheck. Apple's review of the educational code-development workflow
under guideline 2.5.2 remains part of App Review. No preparation lane submits or
releases the app. Only the explicit `studio_submit` lane sends it for review
and records Apple's confirmed queue state in
`build/studio-submission/submission.json`.

Fastlane's current `price_tier` implementation targets an Apple relationship
that is no longer supported. The free schedule is already configured;
`studio_pricing` verifies it using Fastlane Spaceship's current API request
client and does not call the obsolete price-tier action.

## Project and runtime

Project folders live in `Documents/<project>/`. Each folder has a `project.lua`
metadata file returning a plain table with `name`, `bundleId`, `appIcon`, and
`projectIcon`; missing symbol icons use `rocket.fill`, and artwork defaults to
`rocket-sketch`. Three project artworks are available in the project menu: a
rocket sketch, the studio desk, and the lua-objc rocket. `AppIcon.png` and all
three choices are copied into each project when it is created or first
materialized, before the initial Git snapshot. Example project metadata is
bundled under `apps/studio/Documents/` and copied into the app's bundled
workspace by the iPad build.

The bundled Habit Tracker is copied into `Documents/HabitTracker/` on first
launch. Source, the Code pane, and Git all use this folder. The preview maps
these files to its isolated `demo/playground/` module namespace. Habit data
persists locally in `data/`; Studio preferences live in `settings.json`.
Native capabilities still require a host build.

The preview uses a child view controller with compact/phone traits, fitted into
a 393 × 852 point iPhone 16 viewport inside a rounded phone bezel. The bezel and screen
scale together; the controls inside remain interactive. It is native UIKit running on iPad, not an iPhone
Simulator: keyboards, system presentations, and hardware behavior follow the
host device. Test final apps on an iPhone too.

## GitHub publishing

Open GitHub from the rail or project menu. Create a GitHub fine-grained personal
access token in Safari, grant the selected repositories Contents read/write, and
paste it into the secure field. For repository creation, include Administration
write and select repositories the token is allowed to create/access. Connect
Account validates the token before saving it in the device Keychain.

Set the owner, repository name and destination branch, then Create Repository (private by default)
or Link Existing. A new/empty writable repository is the simplest first target.
Check the author name and email, then Commit and Publish. Saved source and real
commit history are pushed with libgit2 over HTTPS, without a Git executable.
View Project on GitHub opens that branch on the actual remote. Credentials, local app data and
Studio settings are excluded. Commit identities are included in history.

Push runs off the UI thread, captures the current commit, and never forces an
update. If GitHub contains unrelated or newer commits, the push is rejected;
choose an empty repository or reconcile the histories outside Studio. This
release publishes local projects; it does not clone, fetch or merge remote work.
Removing a token disables future requests and leaves the remote content intact.

`make studio-test` covers GitHub account/target validation, cancellation, commit
authorship and publishing orchestration with injected transports.
`./lua-objc --test tests/git_remote.test.lua` exercises actual asynchronous
libgit2 pushes to a local bare repository and rejects conflicting history.

## Git

Every project owns `Documents/<project>/.git` from creation. The shared
`Workspace.create` service writes the starting source, initializes the repository
through the libgit2 `Git` module ([src/plugins/git](../../src/plugins/git/README.md)),
and makes the initial commit as "Lua Studio" before registering the project.
Blank, template, and generated project creation must use this service.
`Workspace.open` also establishes history when materializing bundled projects;
later opens preserve both history and uncommitted edits. Studio materializes only the selected project and closes its Git handle when
switching projects.
Source files, `project.lua`, `.gitignore`, and project assets are
versioned directly in the project folder. `/data/` and `/settings.json` are
ignored so habit activity and Studio preferences do not enter source history.
Commit records saved changes, including removed source files, and shows the
short id or "No changes to commit" in the status line. No Git executable or
network connection is required.

There is no binary asset importer, in-app signing service,
or continuous voice conversation. Source export and system dictation are available. Preview Lua
uses separate globals and a module cache, with an initial-render instruction
budget; this is a development environment, not a security boundary for hostile
code. It shares the host's native runtime.

## App structure

`Model.lua` is the Lapis workspace model over `Store.lua`. The root controller
coordinates injected Session, Catalog, Device, Preview and Export services.
Pure presentation lives in `helpers/`; etlua views are grouped into `layouts/`,
`sections/`, `components/` and `sheets/`. The preview evaluates each project with
isolated Lua globals, a separate model store and module cache, and an initial-render
instruction budget. It shares the host's native runtime and is a development
environment, not a security boundary for hostile code.

## Design references

The workspace layout follows patterns common to editors and AI app builders
rather than any one product:

- **Icon-only activity rail** — the activity bar of VS Code and the app rail
  of Microsoft Teams: a narrow column of symbols, the brand mark at the top,
  settings at the foot, and a filled highlight on the selected item.
- **Floating cards on a gradient canvas** and **gradient accents** — dashboard
  and editor shots by Basebern Team, Diana Larussa, and Nasir Uddin in these
  Dribbble searches:
  - [AI app builder IDE](https://dribbble.com/search/ai-app-builder-ide)
  - [AI code editor sidebar](https://dribbble.com/search/ai-code-editor-sidebar)
- **Chat beside a live device preview** — the arrangement shared by AI app
  builders such as Lovable, Bolt, and Replit; see Lovable's overview of the
  category, [Best AI App Builders in 2026](https://lovable.dev/guides/best-ai-app-builders).

Gradients use `<LinearGradient colors="…" startPoint="…" endPoint="…">`
(SwiftUI's `LinearGradient(colors:startPoint:endPoint:)`); see
[docs/agents/xml-syntax.md](../../docs/agents/xml-syntax.md).
