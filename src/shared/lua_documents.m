/*
 * Local documents: small UTF-8 files an app keeps between launches (settings,
 * autosaves), addressed by a relative name that can never escape the root.
 * Each platform root defines LUA_OBJC_DOCUMENT_ROOT(): the app sandbox's
 * Documents folder on iOS, Application Support on the Mac.
 */
static NSString *document_path(lua_State *L) {
	NSString *name = @(luaL_checkstring(L, 1));
	if (!name.length || [name hasPrefix:@"/"] || [name containsString:@"\\"])
		luaL_error(L, "document path must be relative");
	for (NSString *part in [name componentsSeparatedByString:@"/"])
		if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."])
			luaL_error(L, "invalid document path");
	NSString *path = [LUA_OBJC_DOCUMENT_ROOT() stringByAppendingPathComponent:name];
	[[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
		withIntermediateDirectories:YES attributes:nil error:nil];
	return path;
}

static int bridge_document_read(lua_State *L) {
	NSError *error = nil;
	NSString *body = [NSString stringWithContentsOfFile:document_path(L) encoding:NSUTF8StringEncoding error:&error];
	if (body) lua_pushstring(L, body.UTF8String); else lua_pushnil(L);
	if (error) lua_pushstring(L, error.localizedDescription.UTF8String); else lua_pushnil(L);
	return 2;
}

static int bridge_document_write(lua_State *L) {
	NSString *path = document_path(L);
	NSString *body = @(luaL_checkstring(L, 2));
	NSError *error = nil;
	BOOL ok = [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
	lua_pushboolean(L, ok);
	if (error) lua_pushstring(L, error.localizedDescription.UTF8String); else lua_pushnil(L);
	return 2;
}

static int bridge_json_encode(lua_State *L) {
	id obj = lua_to_objc_value(L, 1);
	if (![NSJSONSerialization isValidJSONObject:obj]) return luaL_error(L, "invalid JSON value");
	NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
	lua_pushlstring(L, data.bytes, data.length);
	return 1;
}
