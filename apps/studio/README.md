# Lua Studio for iPad

A standalone Lua app development workspace: interactive phone-sized UIKit preview
on the left, OpenRouter coding agent on the right, and an editable local project.
The iPad runs Lua and etlua directly; ordinary app changes need no native build or
Mac packager.

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

1. Open **Settings**. Lua Studio starts with the `openrouter/free` router;
   enter an OpenRouter API key to use it, or choose any stronger tool-capable
   `provider/model` ID with your key. OpenRouter requires an account/API key
   even for free models.
2. Type a request, or tap **Dictate** and use the system keyboard's microphone.
   Tap **Send** after reviewing the dictated text.
3. The agent reads project files, saves complete file batches, and reloads the
   preview. Tap the real controls inside the preview to try the app.
4. **Files** opens the source editor. Enter a project path and tap **Open** to
   load it or create a new file, then **Save and preview**.
5. **Undo** restores the previous saved file batch. **Stop** cancels the current
   request; already saved edits remain available to undo.

The API key is stored in the device Keychain, separately from project data.
Prompts and files requested by the agent go to OpenRouter. Chat uses its
[tool-calling API](https://openrouter.ai/docs/guides/features/tool-calling).

## Project and runtime

The initial project is `apps/playground/`, with `init.lua`, `Model.lua`,
`Controller.lua`, and `views/Window.etlua`. Files are saved together atomically in
`Documents/playground.json`; Files app sharing is enabled. The bundled starter is
used only for a new workspace. Existing saved projects survive reinstalling the
same bundle ID. Chat and the last 20 undo snapshots live for the current session.

Syntax failures reject the entire edit batch. Runtime errors keep the preceding
preview visible and are returned to the agent for repair. Undo can restore the
last working source. Each preview reload creates fresh project state; it does
not preserve the running model. Native capabilities still require a host build.

The preview uses a child view controller with compact/phone traits, fitted into
a 393 × 740 point viewport inside a rounded phone bezel. The bezel and screen
scale together; the controls inside remain interactive. Reload increments the
visible load count even when the project revision has not changed.
It is native UIKit running on iPad, not an iPhone
Simulator: keyboards, system presentations, and hardware behavior follow the
host device. Test final apps on an iPhone too.

This first version provides one local project and a text/file tool agent.
It has no Git integration, binary asset importer, app signing/export interface,
or continuous voice conversation. Dictation is supplied by iPadOS. Preview Lua
uses separate globals and a module cache, with an initial-render instruction
budget; this is a development environment, not a security boundary for hostile
code. It shares the host's native runtime.

## Verification

`make test` includes project mutation, syntax validation, atomic persistence,
undo, tool exchanges, cancellation, runtime error recovery, and device discovery.
It also invokes the workspace's template-bound buttons with a mocked transport,
including Files, Settings, Reload, Send, Stop, and keyboard dictation, and checks
the signing entitlements needed by Keychain. Simulator builds embed their
entitlements in Mach-O sections; device builds sign with the profile's allowed
app-specific Keychain group. Credential errors appear in Settings instead of
preventing the sheet from opening.
Live API calls require your own OpenRouter key, including calls through
`openrouter/free`.
