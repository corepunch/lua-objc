/* Keychain-backed app credentials. Secrets never enter the project store or
 * its exported files; the bundle identifier is the native service boundary. */
static NSMutableDictionary *credential_query(lua_State *L) {
	NSString *account = @(luaL_checkstring(L, 1));
	if (!account.length) luaL_error(L, "a credential account is required");
	NSString *service = NSBundle.mainBundle.bundleIdentifier ?: @"org.luaobjc.runtime";
	return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: service, (__bridge id)kSecAttrAccount: account } mutableCopy];
}

static void credential_error(lua_State *L, OSStatus status) {
	NSString *message = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
	lua_pushstring(L, (message ?: @"Keychain operation failed").UTF8String);
}

static int bridge_credential_read(lua_State *L) {
	NSMutableDictionary *query = credential_query(L);
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecSuccess) {
		NSData *data = CFBridgingRelease(result);
		lua_pushlstring(L, data.bytes, data.length);
		return 1;
	}
	lua_pushnil(L);
	if (status == errSecItemNotFound) return 1;
	credential_error(L, status);
	return 2;
}

static int bridge_credential_write(lua_State *L) {
	NSMutableDictionary *query = credential_query(L);
	size_t length = 0;
	const char *bytes = luaL_checklstring(L, 2, &length);
	if (!length) return luaL_error(L, "a nonempty credential is required");
	NSData *data = [NSData dataWithBytes:bytes length:length];
	NSDictionary *attributes = @{ (__bridge id)kSecValueData: data,
		(__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly };
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
	if (status == errSecItemNotFound) {
		[query addEntriesFromDictionary:attributes];
		status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	}
	lua_pushboolean(L, status == errSecSuccess);
	if (status == errSecSuccess) return 1;
	credential_error(L, status);
	return 2;
}

static int bridge_credential_remove(lua_State *L) {
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)credential_query(L));
	BOOL ok = status == errSecSuccess || status == errSecItemNotFound;
	lua_pushboolean(L, ok);
	if (ok) return 1;
	credential_error(L, status);
	return 2;
}
