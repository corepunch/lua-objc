# Lua Studio for iPad

A standalone Lua app development workspace: interactive phone-sized UIKit preview
on the left, a coding agent on the right, and editable local projects. The iPad
runs Lua and etlua directly; ordinary app changes need no native build or Mac
packager. The agent speaks to whichever model provider the person chose
(Anthropic, OpenAI, Google Gemini, OpenRouter, or one they added as a plugin),
with the API key kept in the iPad's keychain.

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

Lua Studio is one canvas: an icon-only activity rail down the left, and
beside it a window toolbar over two panes, the running app on a stage sized
to an iPhone 16 and the coding agent in a floating card that fills the rest.
The canvas is a wash of the brand gradient over the system background, so it
holds in light and dark; the rail and the stage have no fill of their own.

The rail carries the Lua Studio mark, the two modes of the agent card (Chat and
Code, with a gradient highlight on the one showing), then Run and Commit, as
Run and Source Control sit in the activity bar of VS Code, then Plugins, and
Settings at its foot. Every item is an icon with an accessibility label.

The toolbar is one Liquid Glass bar spanning the stage and the card, as a Mac
window toolbar spans the content beside a sidebar. The project menu leads: it
lists the projects (choose one to open it), the project's icon choices and
New Project. The status line follows it (Ready, Thinking…, the last commit, or
why a send was refused), and the chat toggle for focusing the preview trails.
Nothing project-wide sits in the stage or the card, so the bar fits an iPad
Pro in portrait with room to spare (`tests/studio_portrait.test.lua` lays the
workspace out at 1032 points and checks).

The stage is the device alone. The card header names the provider and model
answering, with a menu for New Conversation, Choose Model… and Undo Last
Change. The chat is the project's transcript: the request as a gradient
bubble, the agent's reply beside its avatar, a card of changed files with
line counts for each edit (with Undo), and a warning line for an error.
Suggestion chips start a prompt in the composer; Return or the Send button
sends it, and while the agent works the button is Stop. Code shows the
project files with a hideable tree and native Lua/etlua syntax highlighting.
The controls inside the phone preview are interactive.

Every control on screen does something. Share, Deploy, the device picker,
appearance and zoom, attach and dictate were removed rather than shown
disabled: deployment is `make ipad-deploy` from the Mac, and dictation is the
keyboard's own microphone key.

### First run

1. Open Settings from the rail. Choose a provider and model, paste the
   provider's API key into its row, and tap Done. The key goes to the keychain;
   the row then says "Saved in the keychain" and never shows the key again.
   Clearing a row and tapping Done removes its key. "Other…" in the model
   picker, or the Model ID field, takes any model id the provider accepts.
2. Describe a change in the composer. The agent reads the project, applies
   files, and the preview reloads. Each edit is a change card; Undo reverts it.
3. Commit when the project is where you want it.

## Project and runtime

Project folders live in `Documents/<project>/`. Each folder has a `project.lua`
metadata file returning a plain table with `name`, `bundleId`, `appIcon`,
`projectIcon` and `files`; missing symbol icons use `rocket.fill`, and artwork
defaults to `rocket-sketch`. New Project takes a name and a template (Blank App:
the counter in `demo/playground`; Habit Tracker: the bundled three-tab app),
makes `Documents/<Name>/` from the name's letters and digits, writes the files,
icons and metadata, initializes the repository with its first commit, registers
the project in `projects.json`, and opens it. The project menu opens any other
project; the open project's provider, model and transcript are its own.
`AppIcon.png` and all three icon choices are copied into each project when it
is created or first materialized, before the initial Git snapshot. Example
project metadata is bundled under `apps/studio/Documents/` and copied into the
app's bundled workspace by the iPad build.

The bundled Habit Tracker is copied into `Documents/HabitTracker/` on first
launch. Source, the Code pane, and Git all use this folder. The preview maps
these files to its isolated `demo/playground/` module namespace. App data
persists locally in `data/`; the project's agent choice (`provider`, `model`)
lives in `settings.json`. Both are ignored by Git. API keys are never written
to a project: they are keychain items under `org.luaobjc.studio`, one per
provider id (`services/Keys.lua`).

The preview uses a child view controller with compact/phone traits, fitted into
a 393 × 852 point iPhone 16 viewport inside a rounded phone bezel. The bezel and
screen scale together; the controls inside remain interactive. It is native
UIKit running on iPad, not an iPhone Simulator: keyboards, system presentations,
and hardware behavior follow the host device. Test final apps on an iPhone too.

## Providers are plugins

A model provider is one Lua file of the `provider` extension point
(`lua/Plugins.lua`, declared in `services/Providers.lua`). Studio bundles
`plugins/providers/anthropic.lua`, `openai.lua`, `gemini.lua` and
`openrouter.lua`. The person adds a provider by putting a file in
`Documents/Plugins/` (Lua Studio › Plugins in the Files app) and relaunching;
it joins the bundled ones in Settings and on the Plugins sheet, which also
lists files that failed to load and why. A file whose name begins with `_` is
switched off.

The agent keeps the conversation in one neutral shape and never sees a wire
format. A plugin's manifest:

```lua
return {
	api = 1,
	title = "OpenAI",
	symbol = "brain",                              -- SF Symbol in pickers
	website = "https://platform.openai.com/api-keys",
	keyPrefix = "sk-",                             -- the key field's placeholder
	models = { { id = "gpt-5.2", title = "GPT-5.2" } },
	defaultModel = "gpt-5.2",
	-- turn = {model, system, maxTokens, tools = {{name, description, parameters}},
	--   messages = {{role = "user", text}, {role = "assistant", text, calls = {{id, name, arguments}}},
	--               {role = "tool", id, name, result}}}
	request = function(host, turn, key)
		return { url = "https://api.openai.com/v1/chat/completions",
			headers = { Authorization = "Bearer " .. key, ["Content-Type"] = "application/json" },
			body = host.chat.request(turn) }       -- a table is sent as JSON
	end,
	-- `body` is the decoded JSON; return {text, calls = {{id, name, arguments}}} or nil, message
	reply = function(host, status, body) return host.chat.reply(status, body) end,
}
```

The host API is `host.encode`/`host.decode` (JSON) and `host.chat`, the
OpenAI chat-completions dialect (`helpers/ChatCompletions.lua`), so a gateway
that speaks it is a URL, a header and a model list. Anthropic and Gemini map
the turn to their own content blocks in their files. Plugins run in the
sandbox `Plugins.lua` gives every plugin: pure standard libraries, no
`require`, the host API read-only. The protocol is pinned by
`tests/studio_providers.test.lua`, which drives every bundled provider through
a turn with a tool call and its result, parses sample replies and errors, and
loads a user plugin beside a broken one.

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
ignored so app data and the agent choice do not enter source history.
Commit records saved changes, including removed source files, and shows the
short id or "No changes to commit" in the status line. No Git executable or
network connection is required.

Studio has no remote Git operations, binary asset importer, app
signing/export interface, or continuous voice conversation. Dictation is
supplied by iPadOS. Preview Lua uses separate globals and a module cache, with
an initial-render instruction budget; this is a development environment, not a
security boundary for hostile code. It shares the host's native runtime.

## App structure

```
apps/studio/
  init.lua, Controller.lua, Model.lua
  models/        Chat, Code, Toolbar, Preview, Rail, Theme, Projects (templates, folder names),
                 Settings and Plugins (the sheets' data)
  services/      Workspace (Documents, Git), Versions, Preview (isolated runtime),
                 Agent (the turn loop), Providers (the extension point), Keys (keychain),
                 Device (JSON, HTTPS, Documents, keychain from `ns`)
  helpers/       ChatCompletions (the OpenAI dialect), Changes (line counts)
  plugins/providers/   one file per bundled provider
  views/layouts/       Window, Workspace
  views/sections/      Rail, Toolbar, PreviewPane, ChatPane, CodePane
  views/components/    Avatar, ChangeCard, Composer
  views/sheets/        SheetHost, Settings, NewProject, Plugins
```

`Controller.lua` coordinates: it opens projects (`activate`), owns the agent
and the one sheet open at a time (a retained page inside `SheetHost`), and
binds every action. `Model.lua` is the open project: files, undo history,
transcript, provider and model. The controller takes `ns`, `git`, `device`,
`present` and `dismiss` as options so the headless tests drive it with fakes:
`tests/studio_workspace.test.lua` opens the sheets, saves keys and settings,
creates a project; `tests/studio.test.lua` runs the agent loop against a
recorded transport through the real provider plugins.

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
- **Plugins as single files** — the [lite](https://github.com/rxi/lite)
  editor's `plugins/*.lua`: drop a file in, it loads; a broken one is
  reported and the rest start.

Gradients use `<LinearGradient colors="…" startPoint="…" endPoint="…">`
(SwiftUI's `LinearGradient(colors:startPoint:endPoint:)`); see
[docs/agents/xml-syntax.md](../../docs/agents/xml-syntax.md).
