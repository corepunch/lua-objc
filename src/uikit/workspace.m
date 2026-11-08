static int bridge_focus(lua_State *L) {
	UIView *view = check_objc(L, 1);
	[view becomeFirstResponder];
	return 0;
}
/* Ends editing in `view` and beneath it, dismissing the keyboard; a field
 * that is hidden keeps focus otherwise, and its keyboard stays up. */
static int bridge_resign_focus(lua_State *L) {
	UIView *view = check_objc(L, 1);
	[view endEditing:YES];
	return 0;
}
