#pragma mark - Bridge functions (UIKit)

static int bridge_window(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	UIWindowScene *windowScene = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]]
			&& scene.activationState != UISceneActivationStateUnattached) {
			windowScene = (UIWindowScene *)scene;
			break;
		}
	}
	if (!windowScene) {
		return luaL_error(L, "UIKit.Window requires an attached UIWindowScene");
	}

	CGRect frame = CGRectMake(0, 0, width, height);
	UIWindow *w = [[UIWindow alloc] initWithWindowScene:windowScene];
	w.frame = frame;
	w.backgroundColor = UIColor.systemBackgroundColor;
	w.accessibilityLabel = [NSString stringWithUTF8String:title];

	push_objc(L, w, "uiwindow");
	return 1;
}


static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];

	UIImage *img = [UIImage imageWithContentsOfFile:nsPath];
	if (!img) img = [UIImage imageNamed:nsPath];
	if (!img) return luaL_error(L, "failed to load image: %s", path);

	CGSize size = img.size;
	if (size.width > kImageMaxWidth) {
		CGFloat ratio = kImageMaxWidth / size.width;
		size.width = kImageMaxWidth;
		size.height *= ratio;
	}

	UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
	iv.image = img;
	iv.contentMode = UIViewContentModeScaleAspectFit;
	/* Keep layout measurement tied to the bridge's proportional display size,
	 * rather than UIImageView's uncapped intrinsic image size. */
	objc_setAssociatedObject(iv, &kImageLayoutSizeKey,
		[NSValue valueWithCGSize:size], OBJC_ASSOCIATION_RETAIN);

	push_objc(L, iv, "uiview");
	return 1;
}

static UIColor *lua_objc_uikit_system_color(const char *name) {
	if (!name) return UIColor.labelColor;
	if (strcmp(name, "systemRed") == 0) return UIColor.systemRedColor;
	if (strcmp(name, "systemGreen") == 0) return UIColor.systemGreenColor;
	if (strcmp(name, "systemBlue") == 0) return UIColor.systemBlueColor;
	if (strcmp(name, "systemYellow") == 0) return UIColor.systemYellowColor;
	if (strcmp(name, "secondary") == 0) return UIColor.secondaryLabelColor;
	if (strcmp(name, "tertiary") == 0) return UIColor.tertiaryLabelColor;
	if (strcmp(name, "accent") == 0) return UIColor.tintColor;
	if (strcmp(name, "red") == 0) return UIColor.systemRedColor;
	if (strcmp(name, "blue") == 0) return UIColor.systemBlueColor;
	if (strcmp(name, "green") == 0) return UIColor.systemGreenColor;
	if (strcmp(name, "primary") == 0) return UIColor.labelColor;
	if (strcmp(name, "white") == 0) return UIColor.whiteColor;
	if (strcmp(name, "yellow") == 0) return UIColor.systemYellowColor;
	if (strcmp(name, "separator") == 0) return UIColor.separatorColor;
	if (strcmp(name, "background") == 0) return UIColor.systemBackgroundColor;
	return UIColor.labelColor;
}

static int bridge_image_data(lua_State *L) {
	size_t len = 0;
	const char *bytes = luaL_checklstring(L, 1, &len);
	NSData *data = [NSData dataWithBytes:bytes length:len];
	UIImage *img = [UIImage imageWithData:data];
	if (!img) return luaL_error(L, "failed to decode image data");
	CGSize size = img.size;
	if (size.width > kImageMaxWidth) {
		CGFloat ratio = kImageMaxWidth / size.width;
		size.width = kImageMaxWidth;
		size.height *= ratio;
	}
	UIImageView *iv = [[UIImageView alloc]
		initWithFrame:CGRectMake(0, 0, size.width, size.height)];
	iv.image = img;
	iv.contentMode = UIViewContentModeScaleAspectFit;
	objc_setAssociatedObject(iv, &kImageLayoutSizeKey,
		[NSValue valueWithCGSize:size], OBJC_ASSOCIATION_RETAIN);
	push_objc(L, iv, "uiview");
	return 1;
}

static int bridge_system_image(lua_State *L) {
	const char *symbol = luaL_checkstring(L, 1);
	const char *description = luaL_optstring(L, 2, symbol);
	CGFloat pointSize = luaL_optnumber(L, 3, 17);
	const char *weightName = luaL_optstring(L, 4, "regular");
	const char *colorName = luaL_optstring(L, 5, "accent");

	UIImageSymbolWeight weight = UIImageSymbolWeightRegular;
	if (strcmp(weightName, "bold") == 0) weight = UIImageSymbolWeightBold;
	else if (strcmp(weightName, "semibold") == 0)
		weight = UIImageSymbolWeightSemibold;
	else if (strcmp(weightName, "light") == 0)
		weight = UIImageSymbolWeightLight;
	else if (strcmp(weightName, "heavy") == 0)
		weight = UIImageSymbolWeightHeavy;

	UIImageSymbolConfiguration *configuration =
		[UIImageSymbolConfiguration configurationWithPointSize:pointSize
														weight:weight];
	UIImage *image = [UIImage systemImageNamed:
		[NSString stringWithUTF8String:symbol]
		withConfiguration:configuration];
	if (!image) return luaL_error(L, "unknown SF Symbol: %s", symbol);

	UIImageView *view = [[UIImageView alloc]
		initWithFrame:CGRectMake(0, 0, pointSize, pointSize)];
	view.image = image;
	view.contentMode = UIViewContentModeScaleAspectFit;
	view.tintColor = lua_objc_uikit_system_color(colorName);
	view.accessibilityLabel = [NSString stringWithUTF8String:description];
	push_objc(L, view, "uiview");
	return 1;
}

static int bridge_system_color(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	push_objc(L, lua_objc_uikit_system_color(name), "nsobject");
	return 1;
}

static int bridge_add(lua_State *L) {
	id parent = check_objc(L, 1);
	UIView *child = check_view(L, 2);

	if ([parent isKindOfClass:[UIWindow class]]) {
		UIWindow *window = (UIWindow *)parent;
		[window addSubview:child];
		child.frame = window.bounds;
		child.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	} else {
		UIView *container = (UIView *)parent;
		[container addSubview:child];
	}

	return 0;
}

static int bridge_layout(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_optnumber(L, 2, 400);

	UIView *view = (UIView *)obj;
	layout_recursive(view, width);
	return 0;
}

static int bridge_set_content_size(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	UIView *v = (UIView *)obj;
	v.frame = CGRectMake(v.frame.origin.x, v.frame.origin.y, width, height);
	return 0;
}

static int bridge_size_to_fit(lua_State *L) {
	UIView *view = check_view(L, 1);
	[view sizeToFit];
	return 0;
}
