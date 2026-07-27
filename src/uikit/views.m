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

static int bridge_vstack(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(v, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_hstack(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(v, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_hsplit(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(v, &kAxisKey, @"hsplit", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_spacer(lua_State *L) {
	UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
	objc_setAssociatedObject(v, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, v, "uiview");
	return 1;
}

static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];

	UIImage *img = [UIImage imageWithContentsOfFile:nsPath];
	if (!img) img = [UIImage imageNamed:nsPath];
	if (!img) return luaL_error(L, "failed to load image: %s", path);

	CGSize size = img.size;
	if (size.width > 400) {
		CGFloat ratio = 400.0 / size.width;
		size.width = 400;
		size.height *= ratio;
	}

	UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
	iv.image = img;
	iv.contentMode = UIViewContentModeScaleAspectFit;

	push_objc(L, iv, "uiview");
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

#pragma mark - Text update

static int bridge_set_text(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *str = luaL_checkstring(L, 2);
	if ([obj isKindOfClass:[UILabel class]]) {
		[(UILabel *)obj setText:[NSString stringWithUTF8String:str]];
		[(UILabel *)obj sizeToFit];
	}
	return 0;
}
