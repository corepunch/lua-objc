# Lua Studio Privacy Policy

Effective date: November 6, 2026

Lua Studio is a free iPad workspace for creating native app projects. Project
source, icons, Git history, starter-app data, and preferences stay in the app's
local container. Removing the app removes these files, subject to iPadOS backups.
The developer operates no backend for this app and receives no project content.
There is no advertising, analytics, tracking, in-app purchase, or subscription.

## Optional AI assistant

The assistant is optional. Before enabling it, Settings explains the sharing and
asks you to save your own OpenRouter API key. When you press Send, your message,
conversation context, attached text files, and source files requested by the
agent are sent over HTTPS to OpenRouter and the model provider selected through
your OpenRouter account. Responses and generated source return through the same
service. Do not send secrets or information you lack permission to share.

OpenRouter authenticates requests using your API key; requests can be associated
with your OpenRouter account. Provider retention and use depend on the selected
provider and your account settings. See [OpenRouter's privacy policy](https://openrouter.ai/privacy)
and [provider data practices](https://openrouter.ai/docs/guides/privacy/provider-logging).
Provider charges may apply; Lua Studio does not sell AI credits.

The API key is stored in this device's Keychain, accessible while the device is
unlocked. It is not placed in project files, Git history, or project exports.
Remove it in Settings to disable subsequent AI requests. New Conversation clears
the current in-memory conversation. Conversations are not saved across launches.

## Optional Appwrite project

Apps that keep their data online save it to your own
[Appwrite](https://appwrite.io) project, never to one operated by the developer.
Settings asks for its endpoint, project ID and an API key you create in the
Appwrite console. The three are stored in this device's Keychain; the key is not
placed in project files, Git history, exports or AI requests. It is sent only to
your Appwrite endpoint, to create the tables an app needs. Data those apps save
goes to that project under your Appwrite account; see
[Appwrite's privacy policy](https://appwrite.io/privacy). Remove the connection
in Settings.

## Optional GitHub publishing

GitHub is optional and uses your own GitHub personal access token. Connecting
contacts GitHub over HTTPS to validate that token and read your account login,
name, public email and account identifier. The token stays in the device Keychain;
it is never embedded in a remote URL, project source, Git history, exports or AI
requests. Remove it in the GitHub sheet to disable future authenticated requests.

Creating a repository sends its name, owner and selected visibility to GitHub.
New repositories default to private. Publishing sends the selected project's
saved source, artwork and Git commit history to the repository you choose, using
libgit2 directly on your iPad. Commit history contains author names, email
addresses and commit timestamps. The author email defaults to GitHub's no-reply
address when no public email is available. You can edit the author name and
email before publishing. Local application data and Studio settings are excluded.

A public repository makes its source and commit history public. GitHub handles
the uploaded content and account data under [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
Lua Studio does not receive a copy. Removing a token does not delete content
already published to GitHub; manage that content on GitHub.

## Dictation, attachments, and sharing

Pressing the microphone requests Apple's microphone and speech-recognition
permissions. Audio is processed by Apple's Speech service according to system
availability and permissions; recognition may use Apple's servers. Lua Studio
does not save audio recordings. Recognized text becomes an editable draft and
is sent to the AI service only if you press Send.

The native Files picker reads only files you select, as bounded UTF-8 text.
Attachments become request context; they do not replace project files. Share
and Export create a ZIP containing project source, its manifest and app icon.
Runtime data, Git history, Studio settings, and API keys are excluded. Your
chosen share destination handles the exported files under its own policies.

Lua Studio uses file timestamps for project history and a monotonic clock for
runtime timing. Git commit timestamps are included when you publish history to
GitHub. These values are not used for advertising or tracking.

If you contact support on GitHub, your post is handled by GitHub under its own
privacy policy. Do not include passwords, API keys, private source, or personal
information in public issues. For privacy questions, use
[project support](https://github.com/corepunch/lua-objc/issues) or email
igor.chernakov@gmail.com.
