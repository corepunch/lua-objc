// Called synchronously on the existing host's main Lua state; no scene swap,
// window creation, run-loop delay, or per-case deployment is needed.
static int bridge_parity_measure(lua_State *L) {
	@autoreleasepool {
		UIView *root = check_view(L, 1);
		root.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
		root.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
		root.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryLarge;
		root.traitOverrides.layoutDirection = UITraitEnvironmentLayoutDirectionLeftToRight;
		luaL_checktype(L, 2, LUA_TTABLE);
		NSMutableDictionary *result = [lua_to_objc_value(L, 3) mutableCopy];
		CGFloat width = [result[@"width"] doubleValue], height = [result[@"height"] doubleValue];
		root.frame = CGRectMake(0, 0, width, height);
		root.bounds = CGRectMake(0, 0, width, height);
		[root layoutIfNeeded];
		layout_recursive(root, width);
		[root layoutIfNeeded];
		NSMutableArray *probes = [NSMutableArray array];
		for (lua_Integer i = 1; i <= (lua_Integer)lua_rawlen(L, 2); i++) {
			lua_rawgeti(L, 2, i);
			lua_getfield(L, -1, "id");
			NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
			lua_pop(L, 1);
			lua_getfield(L, -1, "view");
			UIView *view = check_view(L, -1);
			CGRect rect = [view convertRect:view.bounds toView:root];
			NSMutableDictionary *probe = [@{@"id":identifier, @"x":@(CGRectGetMinX(rect) - CGRectGetMinX(root.bounds)),
				@"y":@(CGRectGetMinY(rect) - CGRectGetMinY(root.bounds)),
				@"width":@(rect.size.width), @"height":@(rect.size.height)} mutableCopy];
			if ([view isKindOfClass:UILabel.class]) probe[@"text"] = ((UILabel *)view).text ?: @"";
			[probes addObject:probe];
			lua_pop(L, 2);
		}
		result[@"probes"] = probes;
		result[@"platform"] = @"ios";
		result[@"os"] = NSProcessInfo.processInfo.operatingSystemVersionString;
		CGFloat scale = root.traitCollection.displayScale;
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if ([scene isKindOfClass:UIWindowScene.class]) {
				scale = ((UIWindowScene *)scene).screen.scale;
				break;
			}
		}
		result[@"scale"] = @(scale);
		result[@"appearance"] = @"light";
		result[@"locale"] = NSLocale.currentLocale.localeIdentifier;
		result[@"textSize"] = @"large";
		result[@"direction"] = @"ltr";
		result[@"coordinateSpace"] = @"root-top-left-points";
		return parity_push_json(L, result);
	}
}

static int bridge_parity_capture_png(lua_State *L) {
	@autoreleasepool {
		UIView *root = check_view(L, 1);
		NSString *path = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
		CGFloat width = luaL_checknumber(L, 3);
		CGFloat height = luaL_checknumber(L, 4);
		if (width <= 0 || height <= 0) return luaL_error(L, "parity PNG dimensions must be positive");
		root.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
		root.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
		root.frame = CGRectMake(0, 0, width, height);
		root.bounds = CGRectMake(0, 0, width, height);
		[root layoutIfNeeded];
		layout_recursive(root, width);
		[root layoutIfNeeded];

		CGFloat scale = root.window.screen.scale;
		if (scale <= 0) {
			for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
				if ([scene isKindOfClass:UIWindowScene.class]) {
					scale = ((UIWindowScene *)scene).screen.scale;
					break;
				}
			}
		}
		if (scale <= 0) scale = root.traitCollection.displayScale;
		if (scale <= 0) scale = 1.0;

		UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
		format.scale = scale;
		format.opaque = YES;
		UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
			initWithSize:root.bounds.size format:format];
		UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
			UITraitCollection *lightTraits = [UITraitCollection
				traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
			UIColor *background = [[UIColor systemBackgroundColor]
				resolvedColorWithTraitCollection:lightTraits];
			CGContextSetFillColorWithColor(context.CGContext, background.CGColor);
			CGContextFillRect(context.CGContext, (CGRect){CGPointZero, root.bounds.size});
			[root.layer renderInContext:context.CGContext];
		}];
		NSData *png = UIImagePNGRepresentation(image);
		NSError *error = nil;
		if (!png || ![png writeToFile:path options:NSDataWritingAtomic error:&error]) {
			return luaL_error(L, "parity PNG write failed: %s",
				(error.localizedDescription ?: @"could not encode PNG").UTF8String);
		}
		return 0;
	}
}
