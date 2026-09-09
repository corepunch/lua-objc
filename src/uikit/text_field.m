#pragma mark - Editable text field events

@interface LuaTextFieldDelegate : NSObject <UITextFieldDelegate>
@property(nonatomic) int changeRef;
@property(nonatomic) int commandRef;
@property(nonatomic, weak) LuaStateOwner *owner;
@end
@implementation LuaTextFieldDelegate
- (instancetype)init {
	self = [super init];
	if (self) { _changeRef = LUA_NOREF; _commandRef = LUA_NOREF; }
	return self;
}
- (void)dealloc {
	lua_State *L = _owner.L;
	if (!L) return;
	if (_changeRef != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, _changeRef);
	if (_commandRef != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, _commandRef);
}
- (void)textChanged:(UITextField *)field {
	lua_State *L = _owner.L;
	if (!L || _changeRef == LUA_NOREF) return;
	lua_rawgeti(L, LUA_REGISTRYINDEX, _changeRef);
	lua_pushstring(L, (field.text ?: @"").UTF8String);
	push_objc(L, field, "uiview");
	lua_objc_pcall(L, 2, 0, "text field change");
}
- (BOOL)dispatchCommand:(NSString *)command field:(UITextField *)field {
	lua_State *L = _owner.L;
	if (!L || _commandRef == LUA_NOREF) return NO;
	lua_rawgeti(L, LUA_REGISTRYINDEX, _commandRef);
	lua_pushstring(L, command.UTF8String);
	push_objc(L, field, "uiview");
	if (lua_objc_pcall(L, 2, 1, "text field command") != LUA_OK) return NO;
	BOOL handled = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return handled;
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {
	return ![self dispatchCommand:@"submit" field:field];
}
@end

static int bridge_text_field_callbacks(lua_State *L) {
	UITextField *field = lua_objc_check_object(L, 1, UITextField.class, "TextField");
	LuaTextFieldDelegate *old = objc_getAssociatedObject(field, &kTextFieldDelegateKey);
	[field removeTarget:old action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
	LuaTextFieldDelegate *delegate = [[LuaTextFieldDelegate alloc] init];
	delegate.owner = owner_for_state(L);
	if (!lua_isnoneornil(L, 2)) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		delegate.changeRef = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	if (!lua_isnoneornil(L, 3)) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		delegate.commandRef = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	field.delegate = delegate;
	[field addTarget:delegate action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
	objc_setAssociatedObject(field, &kTextFieldDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN);
	return 0;
}
static int bridge_text_field_test_input(lua_State *L) {
	UITextField *field = lua_objc_check_object(L, 1, UITextField.class, "TextField");
	field.text = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	[field sendActionsForControlEvents:UIControlEventEditingChanged];
	return 0;
}
static int bridge_text_field_test_command(lua_State *L) {
	UITextField *field = lua_objc_check_object(L, 1, UITextField.class, "TextField");
	LuaTextFieldDelegate *delegate = objc_getAssociatedObject(field, &kTextFieldDelegateKey);
	lua_pushboolean(L, [delegate dispatchCommand:[NSString stringWithUTF8String:luaL_checkstring(L, 2)] field:field]);
	return 1;
}
