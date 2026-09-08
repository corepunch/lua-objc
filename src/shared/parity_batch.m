// Foundation preserves empty probe arrays and performs atomic result writes.
static int bridge_parity_documents(lua_State *L) {
	NSString *path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	lua_pushstring(L, path.UTF8String);
	return 1;
}

static int bridge_parity_read_json(lua_State *L) {
	NSString *path = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	NSError *error = nil;
	NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
	id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
	if (!object) return luaL_error(L, "parity read: %s", error.localizedDescription.UTF8String);
	push_objc_value(L, object);
	return 1;
}

static int bridge_parity_write(lua_State *L) {
	NSString *path = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	size_t length;
	const char *bytes = luaL_checklstring(L, 2, &length);
	NSError *error = nil;
	if (![[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
		withIntermediateDirectories:YES attributes:nil error:&error] ||
		![[NSData dataWithBytes:bytes length:length] writeToFile:path options:NSDataWritingAtomic error:&error]) {
		return luaL_error(L, "parity write: %s", error.localizedDescription.UTF8String);
	}
	return 0;
}

static int parity_push_json(lua_State *L, NSDictionary *result) {
	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:&error];
	if (!data) return luaL_error(L, "parity JSON: %s", error.localizedDescription.UTF8String);
	lua_pushlstring(L, data.bytes, data.length);
	return 1;
}

static int bridge_parity_json(lua_State *L) {
	return parity_push_json(L, lua_to_objc_value(L, 1));
}
