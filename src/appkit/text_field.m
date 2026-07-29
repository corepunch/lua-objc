#pragma mark - Editable Text Field Callbacks

@interface LuaTextFieldDelegate : NSObject <NSTextFieldDelegate>
@property (nonatomic) int changeRef;
@property (nonatomic) int commandRef;
@property (nonatomic, weak) LuaStateOwner *owner;
- (BOOL)dispatchCommand:(NSString *)command field:(NSTextField *)field;
@end

@implementation LuaTextFieldDelegate

- (instancetype)init {
	self = [super init];
	if (self) {
		_changeRef = LUA_NOREF;
		_commandRef = LUA_NOREF;
	}
	return self;
}

- (void)dealloc {
	lua_State *callL = _owner.L;
	if (!callL) return;
	if (_changeRef != LUA_NOREF) {
		luaL_unref(callL, LUA_REGISTRYINDEX, _changeRef);
	}
	if (_commandRef != LUA_NOREF) {
		luaL_unref(callL, LUA_REGISTRYINDEX, _commandRef);
	}
}

- (void)controlTextDidChange:(NSNotification *)notification {
	lua_State *callL = _owner.L;
	if (_changeRef == LUA_NOREF || !callL) return;
	NSTextField *field = notification.object;
	lua_rawgeti(callL, LUA_REGISTRYINDEX, _changeRef);
	lua_pushstring(callL, field.stringValue.UTF8String);
	push_objc(callL, field, "nsview");
	lua_objc_pcall(callL, 2, 0, "text field change");
}

- (BOOL)dispatchCommand:(NSString *)command field:(NSTextField *)field {
	lua_State *callL = _owner.L;
	if (_commandRef == LUA_NOREF || !callL) return NO;
	lua_rawgeti(callL, LUA_REGISTRYINDEX, _commandRef);
	lua_pushstring(callL, command.UTF8String);
	push_objc(callL, field, "nsview");
	if (lua_objc_pcall(callL, 2, 1, "text field command") != LUA_OK) {
		return NO;
	}
	BOOL handled = lua_toboolean(callL, -1);
	lua_pop(callL, 1);
	return handled;
}

- (BOOL)control:(NSControl *)control
	   textView:(NSTextView *)textView
doCommandBySelector:(SEL)selector
{
	NSString *selectorName = NSStringFromSelector(selector);
	NSString *command = selectorName;
	if ([selectorName isEqualToString:@"insertNewline:"]) command = @"submit";
	else if ([selectorName isEqualToString:@"cancelOperation:"]) command = @"cancel";
	else if ([selectorName isEqualToString:@"moveUp:"]) command = @"moveUp";
	else if ([selectorName isEqualToString:@"moveDown:"]) command = @"moveDown";
	return [self dispatchCommand:command field:(NSTextField *)control];
}

@end

static LuaTextFieldDelegate *text_field_delegate(NSTextField *field) {
	return objc_getAssociatedObject(field, &kKeys[kTextFieldDelegateKey]);
}

static int bridge_text_field_callbacks(lua_State *L) {
	id obj = check_objc(L, 1);
	if (![obj isKindOfClass:[NSTextField class]]) {
		return luaL_error(L, "textFieldCallbacks requires an NSTextField");
	}
	int changeRef, commandRef;
	LUA_OPT_CALLBACK_REF(L, 2, changeRef);
	LUA_OPT_CALLBACK_REF(L, 3, commandRef);

	LuaTextFieldDelegate *delegate = [[LuaTextFieldDelegate alloc] init];
	delegate.owner = owner_for_state(L);
	delegate.changeRef = changeRef;
	delegate.commandRef = commandRef;
	NSTextField *field = (NSTextField *)obj;
	field.delegate = delegate;
	objc_setAssociatedObject(field, &kKeys[kTextFieldDelegateKey], delegate,
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_text_field_test_input(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *value = luaL_checkstring(L, 2);
	if (![obj isKindOfClass:[NSTextField class]]) {
		return luaL_error(L, "textFieldTestInput requires an NSTextField");
	}
	NSTextField *field = (NSTextField *)obj;
	field.stringValue = [NSString stringWithUTF8String:value];
	LuaTextFieldDelegate *delegate = text_field_delegate(field);
	[delegate controlTextDidChange:
		[NSNotification notificationWithName:NSControlTextDidChangeNotification
			object:field]];
	return 0;
}

static int bridge_text_field_test_command(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *command = luaL_checkstring(L, 2);
	if (![obj isKindOfClass:[NSTextField class]]) {
		return luaL_error(L, "textFieldTestCommand requires an NSTextField");
	}
	BOOL handled = [text_field_delegate((NSTextField *)obj)
		dispatchCommand:[NSString stringWithUTF8String:command]
				 field:(NSTextField *)obj];
	lua_pushboolean(L, handled);
	return 1;
}
