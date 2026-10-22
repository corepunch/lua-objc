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

/* The absolute path of a document or folder, for native services such as
 * the Git module that open files themselves. */
static int bridge_document_path(lua_State *L) {
	lua_pushstring(L, document_path(L).fileSystemRepresentation);
	return 1;
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

/* Binary assets such as project app icons use Lua strings with an explicit
 * byte length; the text document API above intentionally remains UTF-8. */
static int bridge_document_write_data(lua_State *L) {
	NSString *path = document_path(L);
	size_t length = 0;
	const char *bytes = luaL_checklstring(L, 2, &length);
	NSData *data = [NSData dataWithBytes:bytes length:length];
	NSError *error = nil;
	BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&error];
	lua_pushboolean(L, ok);
	if (error) lua_pushstring(L, error.localizedDescription.UTF8String); else lua_pushnil(L);
	return 2;
}

static int bridge_document_exists(lua_State *L) {
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:document_path(L)];
	lua_pushboolean(L, exists);
	return 1;
}

/* The entries of a Documents folder, sorted as Finder sorts, hidden files
 * left out: {name, directory} each. Apps that let the user drop files in
 * (plugins in a Plugins folder) read the folder with this. A folder that
 * does not exist yet lists as empty. */
static int bridge_document_list(lua_State *L) {
	NSString *path = document_path(L);
	NSFileManager *fm = NSFileManager.defaultManager;
	NSArray<NSString *> *names = [[fm contentsOfDirectoryAtPath:path error:nil]
		sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	lua_newtable(L);
	lua_Integer index = 0;
	for (NSString *name in names) {
		if ([name hasPrefix:@"."]) continue;
		BOOL directory = NO;
		[fm fileExistsAtPath:[path stringByAppendingPathComponent:name] isDirectory:&directory];
		lua_newtable(L);
		lua_pushstring(L, name.UTF8String);
		lua_setfield(L, -2, "name");
		lua_pushboolean(L, directory);
		lua_setfield(L, -2, "directory");
		lua_rawseti(L, -2, ++index);
	}
	return 1;
}

static int bridge_json_encode(lua_State *L) {
	id obj = lua_to_objc_value(L, 1);
	if (![NSJSONSerialization isValidJSONObject:obj]) return luaL_error(L, "invalid JSON value");
	NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
	lua_pushlstring(L, data.bytes, data.length);
	return 1;
}
