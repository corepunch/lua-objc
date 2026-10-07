# Translator runtime data

`LTPRO.EXE`, `BASE.DIC`, and `BASE.RUS` are the original unpacked LTGOLD
assets required by `en-ru-translator`'s `core.engine`. They are bundled here
because the upstream repository excludes its local `LTGOLD/` directory.
The executable supplies static tables only; translation runs entirely in Lua.

The service reads these files through the platform reader on first nonempty
input and passes their bytes to the engine, so bundled and streamed iOS apps
use the same files as macOS.
