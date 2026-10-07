# Hygiene

- No secrets, tokens, or user paths in the repository or in a template.
- A new app surface needs a headless regression test and, if layout changed, a dump at two sizes.
- Delete replaced Lua view modules in the same change. Do not leave a forwarding stub.
- Unknown tags must fail. Do not catch the error and draw a placeholder.
- Platform conditionals belong in the bridge, not in a shared etlua file. Pass `ns` into `xml.render`.
- Follow `skills/maintain-lua-objc-framework` before adding a native constructor. Try `_create`, KVC, `_perform`, and `_callback` first.
