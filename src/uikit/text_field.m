#pragma mark - Editable text field events

@interface LuaTextFieldDelegate : NSObject <UITextFieldDelegate>
@property(nonatomic, strong) LuaReg *changeReg;
@property(nonatomic, strong) LuaReg *commandReg;
@property(nonatomic, strong) LuaReg *focusReg;
@end
@implementation LuaTextFieldDelegate
- (void)dealloc {
	[_changeReg dispose];
	[_commandReg dispose];
	[_focusReg dispose];
}
- (void)editingDidBegin:(UITextField *)field {
	(void)field;
	lua_State *L = lua_reg_live_state(_focusReg);
	if (!L || !lua_reg_push(_focusReg)) return;
	lua_objc_pcall(L, 0, 0, "text field focus");
}
- (void)textChanged:(UITextField *)field {
	lua_State *L = lua_reg_live_state(_changeReg);
	if (!L || !lua_reg_push(_changeReg)) return;
	lua_pushstring(L, (field.text ?: @"").UTF8String);
	push_objc(L, field, "uiview");
	lua_objc_pcall(L, 2, 0, "text field change");
}
- (BOOL)dispatchCommand:(NSString *)command field:(UITextField *)field {
	lua_State *L = lua_reg_live_state(_commandReg);
	if (!L || !lua_reg_push(_commandReg)) return NO;
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
	[field removeTarget:old action:@selector(editingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];
	LuaTextFieldDelegate *delegate = [[LuaTextFieldDelegate alloc] init];
	delegate.changeReg = lua_reg_opt(L, 2);
	delegate.commandReg = lua_reg_opt(L, 3);
	delegate.focusReg = lua_reg_opt(L, 4);
	field.delegate = delegate;
	[field addTarget:delegate action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
	[field addTarget:delegate action:@selector(editingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];
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
static int bridge_text_field_test_focus(lua_State *L) {
	UITextField *field = lua_objc_check_object(L, 1, UITextField.class, "TextField");
	[field sendActionsForControlEvents:UIControlEventEditingDidBegin];
	return 0;
}
