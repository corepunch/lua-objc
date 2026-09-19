#pragma mark - Local documents, credentials, and HTTP requests

static NSString *document_path(lua_State *L) {
	NSString *name = @(luaL_checkstring(L, 1));
	if (!name.length || ![name.lastPathComponent isEqualToString:name] || [name isEqualToString:@".."])
		luaL_error(L, "document name must be a filename");
	NSString *root = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	[[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
	return [root stringByAppendingPathComponent:name];
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
static int bridge_credential(lua_State *L) {
	NSMutableDictionary *query = [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService:NSBundle.mainBundle.bundleIdentifier ?: @"lua-objc",
		(__bridge id)kSecAttrAccount:@(luaL_checkstring(L, 1))} mutableCopy];
	if (!lua_isnoneornil(L, 2)) {
		NSData *data = [@(luaL_checkstring(L, 2)) dataUsingEncoding:NSUTF8StringEncoding];
		OSStatus status;
		if (!data.length) status = SecItemDelete((__bridge CFDictionaryRef)query);
		else {
			status = SecItemUpdate((__bridge CFDictionaryRef)query,
				(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
			if (status == errSecItemNotFound) {
				query[(__bridge id)kSecValueData] = data;
				query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
				status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
			}
		}
		if (status != errSecSuccess && !(status == errSecItemNotFound && !data.length))
			return luaL_error(L, "Keychain error %d", (int)status);
		return 0;
	}
	query[(__bridge id)kSecReturnData] = @YES;
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) { lua_pushstring(L, ""); return 1; }
	if (status != errSecSuccess) return luaL_error(L, "Keychain error %d", (int)status);
	NSData *data = CFBridgingRelease(result);
	lua_pushlstring(L, data.bytes, data.length);
	return 1;
}
static int bridge_json_encode(lua_State *L) {
	id obj = lua_to_objc_value(L, 1);
	if (![NSJSONSerialization isValidJSONObject:obj]) return luaL_error(L, "invalid JSON value");
	NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
	lua_pushlstring(L, data.bytes, data.length);
	return 1;
}
static int bridge_http_request(lua_State *L) {
	NSURL *url = [NSURL URLWithString:@(luaL_checkstring(L, 1))];
	if (!url || ![url.scheme isEqualToString:@"https"]) return luaL_error(L, "HTTP request requires HTTPS");
	luaL_checktype(L, 4, LUA_TFUNCTION);
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	request.timeoutInterval = 120;
	request.allHTTPHeaderFields = lua_to_objc_value(L, 2);
	request.HTTPBody = [@(luaL_checkstring(L, 3)) dataUsingEncoding:NSUTF8StringEncoding];
	LuaStateOwner *owner = owner_for_state(L);
	if (!owner) return luaL_error(L, "async runtime is not initialized");
	LuaReg *reg = lua_reg_create(L, 4, YES);
	__block NSURLSessionDataTask *task = nil;
	task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[owner _untrack:task];
			task = nil;
			lua_State *callL = lua_reg_live_state(reg);
			if (callL && !owner.cancelled) {
				lua_reg_push(reg);
				NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
				if (body) lua_pushstring(callL, body.UTF8String); else lua_pushnil(callL);
				if (error) lua_pushstring(callL, error.localizedDescription.UTF8String); else lua_pushnil(callL);
				lua_pushinteger(callL, [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0);
				lua_objc_pcall(callL, 3, 0, "HTTP request");
			}
			[reg dispose];
		});
	}];
	[owner trackTask:task];
	[task resume];
	push_objc(L, task, "nsobject");
	return 1;
}
static int bridge_cancel_request(lua_State *L) {
	id task = check_objc(L, 1);
	if (![task isKindOfClass:NSURLSessionTask.class]) return luaL_error(L, "expected HTTP request");
	[task cancel];
	return 0;
}
static int bridge_focus(lua_State *L) {
	UIView *view = check_objc(L, 1);
	[view becomeFirstResponder];
	return 0;
}
