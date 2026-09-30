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

Lua Studio is three columns on one canvas: an icon-only activity rail, the
running app on a stage sized to an iPhone 16, and the coding agent in a floating
card that fills the rest. The canvas is a wash of the brand gradient over the
system background, so it holds in light and dark; the rail and the stage have no
fill of their own.

The rail carries the Lua Studio mark, the two modes of the agent card (Chat and
Code, with a gradient highlight on the one showing), the workspace destinations
(Templates, Examples, Plugins), and Settings at its foot. Every item is an icon
with an accessibility label.

Liquid Glass bars above and below the device hold the preview actions. The top
bar has the project menu, which lists the projects and New Project, plus the
preview status, Run, and the chat toggle for focusing the preview. The bottom
bar has the device, reload, appearance, and zoom controls. The card header has
the agent's avatar and the project actions Commit, Share, and Deploy. The chat
shows the request as a gradient bubble, the agent's reply beside its avatar,
and a card of changed files with line counts (it opens at the latest turn), followed by suggestions and a
glass composer, in a centred reading column. Run, reload, Commit, the rail's
mode switch, and the chat toggle work. Project switching, the rail
destinations, Share, Deploy, and the composer are still placeholders. Code
shows the project files with a hideable tree and native Lua/etlua syntax
highlighting.
The controls inside the phone preview are interactive.

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

## Git

Every project owns `Documents/<project>/.git` from creation. The shared
`Workspace.create` service writes the starting source, initializes the repository
through the libgit2 `Git` module ([src/plugins/git](../../src/plugins/git/README.md)),
and makes the initial commit as "Lua Studio" before registering the project.
Blank, template, and generated project creation must use this service.
`Workspace.open` also establishes history when materializing bundled projects;
later opens preserve both history and uncommitted edits. Studio materializes all
projects in its catalog at startup, including their repositories.
Source files, `project.lua`, `.gitignore`, and project assets are
versioned directly in the project folder. `/data/` and `/settings.json` are
ignored so habit activity and Studio preferences do not enter source history.
Commit records saved changes, including removed source files, and shows the
short id or "No changes to commit" in the status line. No Git executable or
network connection is required.

This first version provides one local project and a text/file tool agent.
It has no remote Git operations, binary asset importer, app signing/export interface,
or continuous voice conversation. Dictation is supplied by iPadOS. Preview Lua
uses separate globals and a module cache, with an initial-render instruction
budget; this is a development environment, not a security boundary for hostile
code. It shares the host's native runtime.

## App structure

The window composes the rail, the preview stage, and the chat templates on the
canvas; `ChangeCard`, `Composer`, and `Avatar` are partials of the chat. Each
column has its own controller and presentation model: `models/Rail.lua` lists
the modes and destinations, `models/Preview.lua` picks the current project for
the stage, and `models/Chat.lua` derives file names, folders, symbols, and line
totals for the change card. `models/Theme.lua` holds the brand gradient, the
canvas colors, and the tint of Studio's own controls; the previewed app keeps
its own accent. `Controller.lua` coordinates the columns and loads the starter
preview.

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
