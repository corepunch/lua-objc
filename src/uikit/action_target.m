#pragma mark - LuaButtonTarget

@interface LuaButtonTarget : NSObject
+ (instancetype)shared;
@end

@implementation LuaButtonTarget

+ (instancetype)shared {
	static LuaButtonTarget *instance = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ instance = [[self alloc] init]; });
	return instance;
}

- (void)onAction:(id)sender {
	id refObj = objc_getAssociatedObject(sender, &kCallbackKey);
	if (!refObj || !gL) return;
	int ref = [refObj intValue];

	lua_rawgeti(gL, LUA_REGISTRYINDEX, ref);
	lua_objc_pcall(gL, 0, 0, "button");
}

@end
