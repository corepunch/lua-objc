# Lua Studio product requirements

- Studio is a landscape-only iPad app. Never allow portrait or portrait-upside-down.
  Keep the window's landscape lock and both bundled orientation lists aligned.
  Verify the real landscape scene; screenshots and test window sizes must be landscape.
- Use native iOS presentations and actions. Destructive confirmation is a system
  alert with native Cancel and Delete actions. Settings uses a native navigation
  bar with the system Done item. Do not build replacement dialog button rows.
- Desktop verification reads `STUDIO_REVIEW_GITHUB_TOKEN` from the environment.
  Never retrieve the review token with the `security` CLI or trigger Keychain dialogs.
- Fastlane API authentication reads `APP_STORE_CONNECT_API_KEY_*` from ENV only.
  Local credentials live in `~/.config/lua-objc/fastlane.env` (0600), loaded by
  `.zshenv` and the ignored `fastlane/.env` link. Never log or commit their values.
