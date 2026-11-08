# Lua Studio product requirements

- On iPad, Studio is landscape only. Never allow portrait or portrait-upside-down
  there. Keep the window's landscape lock and the `~ipad` orientation list aligned,
  and verify the real landscape scene: iPad screenshots and test window sizes are
  landscape.
- On iPhone, Studio is portrait. The project runs full screen in the preview host
  under the Studio capsule (`views/layouts/Phone.etlua`,
  `controllers/PhoneController.lua`); the conversation is a sheet over it. The
  root controller picks the layout by `ns.idiom`. Verify with portrait iPhone
  Simulator screenshots.
- Use native iOS presentations and actions. Destructive confirmation is a system
  alert with native Cancel and Delete actions. Settings uses a native navigation
  bar with the system Done item. Do not build replacement dialog button rows.
- Desktop verification reads `STUDIO_REVIEW_GITHUB_TOKEN` from the environment.
  Never retrieve the review token with the `security` CLI or trigger Keychain dialogs.
- Fastlane API authentication reads `APP_STORE_CONNECT_API_KEY_*` from ENV only.
  Local credentials live in `~/.config/lua-objc/fastlane.env` (0600), loaded by
  `.zshenv` and the ignored `fastlane/.env` link. Never log or commit their values.
