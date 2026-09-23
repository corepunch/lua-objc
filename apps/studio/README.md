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

Lua Studio currently presents a visual workspace prototype: project navigation,
a live starter-app preview, and a chat panel. Focus Preview, Compact sidebar,
and Run work from the shared top toolbar. Project creation, Git, Share, Deploy,
and chat controls remain placeholders. The preview controls inside the phone
remain interactive.

## Project and runtime

Project folders live in `Documents/<project>/`. Each folder has a `project.lua`
metadata file returning a plain table with `name`, `bundleId`, and `appIcon`;
missing icons use the `app.dashed` SF Symbol. Example project metadata is bundled
under `apps/studio/Documents/` and copied into the app's bundled workspace by
the iPad build.

The preview loads `demo/playground/` from the locally saved workspace, falling
back to the bundled starter project when no saved workspace exists. Each preview
load creates fresh project state. Native capabilities still require a host build.

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

## App structure

The window composes focused sidebar, preview, and chat templates. Each pane has
its own controller and presentation model; `Controller.lua` coordinates those
panes and loads the starter preview.
