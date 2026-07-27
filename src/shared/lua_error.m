/* Protected Lua calls keep the host alive, but they must not make failures
 * invisible. Keep reporting at the native boundary so AppKit and UIKit
 * callbacks share the same stderr contract, including non-string errors. */
static void report_lua_error(lua_State *L, const char *context) {
	const char *message = lua_tostring(L, -1);
	if (message) {
		fprintf(stderr, "%s error: %s\n", context, message);
	} else {
		fprintf(stderr, "%s error: <%s>\n", context, luaL_typename(L, -1));
	}
	fflush(stderr);
}
