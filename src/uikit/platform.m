#pragma mark - Show

static int bridge_show(lua_State *L) {
	UIWindow *w = (__bridge UIWindow *)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	[w makeKeyAndVisible];
	return 0;
}

#pragma mark - Native values

static int bridge_font(lua_State *L) {
	CGFloat size = luaL_checknumber(L, 1);
	const char *weightStr = luaL_optstring(L, 2, NULL);
	BOOL italic = lua_toboolean(L, 3);

	UIFontWeight w = UIFontWeightRegular;
	if (weightStr) {
		if (strcmp(weightStr, "bold") == 0) w = UIFontWeightBold;
		else if (strcmp(weightStr, "semibold") == 0) w = UIFontWeightSemibold;
		else if (strcmp(weightStr, "light") == 0) w = UIFontWeightLight;
		else if (strcmp(weightStr, "heavy") == 0) w = UIFontWeightHeavy;
	}

	UIFont *font = [UIFont systemFontOfSize:size weight:w];
	if (italic) {
		UIFontDescriptor *descriptor = [font.fontDescriptor
			fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
		if (descriptor) font = [UIFont fontWithDescriptor:descriptor size:size];
	}
	push_objc(L, font, "nsobject");
	return 1;
}
