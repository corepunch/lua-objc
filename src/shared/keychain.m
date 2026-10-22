/*
 * Secrets an app keeps for its user, such as API keys: generic-password
 * items in the keychain, addressed by service and account. The value is
 * bytes; Lua passes and receives it as a string. Both platforms share this
 * fragment; Security.framework is linked by each platform root.
 */
#import <Security/Security.h>

static NSMutableDictionary *keychain_query(lua_State *L) {
	NSString *service = @(luaL_checkstring(L, 1));
	NSString *account = @(luaL_checkstring(L, 2));
	if (!service.length || !account.length) luaL_error(L, "keychain service and account are required");
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: service,
		(__bridge id)kSecAttrAccount: account,
	} mutableCopy];
}

static int keychain_result(lua_State *L, OSStatus status) {
	lua_pushboolean(L, status == errSecSuccess);
	if (status == errSecSuccess) lua_pushnil(L);
	else lua_pushfstring(L, "keychain error %d", (int)status);
	return 2;
}

/* The stored value, or nil when there is none; nil and a message on failure. */
static int bridge_keychain_get(lua_State *L) {
	NSMutableDictionary *query = keychain_query(L);
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) { lua_pushnil(L); return 1; }
	if (status != errSecSuccess) {
		lua_pushnil(L);
		lua_pushfstring(L, "keychain error %d", (int)status);
		return 2;
	}
	NSData *data = CFBridgingRelease(result);
	lua_pushlstring(L, data.bytes, data.length);
	return 1;
}

/* Replaces the value, adding the item when it does not exist yet. */
static int bridge_keychain_set(lua_State *L) {
	NSMutableDictionary *query = keychain_query(L);
	size_t length = 0;
	const char *bytes = luaL_checklstring(L, 3, &length);
	NSData *data = [NSData dataWithBytes:bytes length:length];
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
		(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
	if (status == errSecItemNotFound) {
		query[(__bridge id)kSecValueData] = data;
#if TARGET_OS_IPHONE
		/* Readable once the device has been unlocked after boot, and never
		 * carried to another device by a backup: a key belongs to this iPad. */
		query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
#endif
		status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	}
	return keychain_result(L, status);
}

/* Removes the item; an item that is already absent counts as removed. */
static int bridge_keychain_delete(lua_State *L) {
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)keychain_query(L));
	if (status == errSecItemNotFound) status = errSecSuccess;
	return keychain_result(L, status);
}
