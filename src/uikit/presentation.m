#pragma mark - UIKit presentation bridge

static UIViewController *lua_uikit_presenter(void) {
	UIWindow *window = LRTApplicationWindow();
	UIViewController *presenter = window.rootViewController;
	while (presenter.presentedViewController)
		presenter = presenter.presentedViewController;
	return presenter;
}

static int bridge_UIKitPresentation_presentSheet(lua_State *L) {
	UIViewController *sheet = check_view_controller(L, 1);
	UIViewController *presenter = lua_uikit_presenter();
	if (!presenter) return luaL_error(L, "no UIKit presenter is installed");

	static const char *styles[] = { "pageSheet", "formSheet", NULL };
	int style = 0;
	if (lua_istable(L, 2)) {
		lua_getfield(L, 2, "presentationStyle");
		style = luaL_checkoption(L, -1, "pageSheet", styles);
		lua_pop(L, 1);
	}
	sheet.modalPresentationStyle = style == 1 ? UIModalPresentationFormSheet : UIModalPresentationPageSheet;
	if (lua_istable(L, 2)) {
		lua_getfield(L, 2, "title");
		if (!lua_isnoneornil(L, -1))
			sheet.title = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
		lua_pop(L, 1);
	}
	[presenter presentViewController:sheet animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
	UISheetPresentationController *presentation = sheet.sheetPresentationController;
	if (presentation && lua_istable(L, 2)) {
		lua_getfield(L, 2, "detents");
		if (lua_istable(L, -1)) {
			NSMutableArray<UISheetPresentationControllerDetent *> *detents =
				[NSMutableArray array];
			for (lua_Integer i = 1; i <= luaL_len(L, -1); i++) {
				lua_rawgeti(L, -1, i);
				const char *name = luaL_checkstring(L, -1);
				if (strcmp(name, "medium") == 0)
					[detents addObject:UISheetPresentationControllerDetent.mediumDetent];
				else if (strcmp(name, "large") == 0)
					[detents addObject:UISheetPresentationControllerDetent.largeDetent];
				lua_pop(L, 1);
			}
			if (detents.count > 0) presentation.detents = detents;
		}
		lua_pop(L, 1);
		/* Apple Maps' sheet: content stays interactive beneath the sheet
		 * up to this detent, and UIKit dims it only above. */
		lua_getfield(L, 2, "largestUndimmedDetent");
		if (lua_isstring(L, -1)) {
			const char *name = lua_tostring(L, -1);
			if (strcmp(name, "medium") == 0)
				presentation.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
			else if (strcmp(name, "large") == 0)
				presentation.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
		}
		lua_pop(L, 1);
		lua_getfield(L, 2, "dragIndicator");
		if (lua_isboolean(L, -1))
			presentation.prefersGrabberVisible = lua_toboolean(L, -1);
		else if (lua_isstring(L, -1))
			presentation.prefersGrabberVisible = strcmp(lua_tostring(L, -1), "hidden") != 0;
		else
			presentation.prefersGrabberVisible = YES;
		lua_pop(L, 1);
	}
	push_objc(L, sheet, "uiviewcontroller");
	return 1;
}

static int bridge_UIKitPresentation_dismiss(lua_State *L) {
	UIViewController *presenter = lua_uikit_presenter();
	if (presenter.presentingViewController)
		[presenter dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
	return 0;
}

static int bridge_UIKitPresentation_confirm(lua_State *L) {
	const char *title = luaL_optstring(L, 1, "Confirm");
	const char *message = luaL_optstring(L, 2, "");
	const char *primary = luaL_optstring(L, 3, "OK");
	const char *cancel = luaL_optstring(L, 4, "Cancel");
	LuaReg *callback = lua_reg_opt(L, 5);

	UIViewController *presenter = lua_uikit_presenter();
	if (!presenter) return luaL_error(L, "no UIKit presenter is installed");
	UIAlertController *alert = [UIAlertController
		alertControllerWithTitle:[NSString stringWithUTF8String:title]
		message:[NSString stringWithUTF8String:message]
		preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction *primaryAction = [UIAlertAction
		actionWithTitle:[NSString stringWithUTF8String:primary]
		style:UIAlertActionStyleDestructive
		handler:^(__unused UIAlertAction *action) {
			lua_State *callL = lua_reg_live_state(callback);
			if (callL && lua_reg_push(callback))
				lua_objc_pcall(callL, 0, 0, "confirm");
			[callback dispose];
		}];
	[alert addAction:primaryAction];
	if (cancel && cancel[0]) {
		[alert addAction:[UIAlertAction
			actionWithTitle:[NSString stringWithUTF8String:cancel]
			style:UIAlertActionStyleCancel handler:nil]];
	}
	[presenter presentViewController:alert animated:NO completion:nil];
	return 0;
}

/* Foundation's coordinated uploading read makes the ZIP; the system activity
 * controller owns destinations, presentation, and completion. */
static int bridge_UIKitPresentation_shareFiles(lua_State *L) {
	NSArray *items = lua_to_objc_value(L, 1);
	NSString *name = @(luaL_optstring(L, 2, "Project"));
	if (![items isKindOfClass:NSArray.class] || !items.count)
		return luaL_error(L, "shareFiles requires a nonempty file list");
	if (!document_relative_name_valid(name) || name.pathComponents.count != 1)
		return luaL_error(L, "archive name must be a filename");
	UIViewController *presenter = lua_uikit_presenter();
	if (!presenter) return luaL_error(L, "no UIKit presenter is installed");
	for (NSDictionary *item in items) {
		if (![item isKindOfClass:NSDictionary.class] || (![item[@"text"] isKindOfClass:NSString.class] && !document_relative_name_valid(item[@"source"]))
			|| !document_relative_name_valid(item[@"name"]))
			return luaL_error(L, "shareFiles paths must be safe relative names");
	}
	NSFileManager *manager = NSFileManager.defaultManager;
	NSURL *temporary = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
	NSURL *folder = [temporary URLByAppendingPathComponent:name isDirectory:YES];
	NSError *error = nil;
	[manager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error];
	for (NSDictionary *item in items) {
		if (error) break;
		NSURL *source = item[@"source"] ? [NSURL fileURLWithPath:[LUA_OBJC_DOCUMENT_ROOT() stringByAppendingPathComponent:item[@"source"]]] : nil;
		NSURL *destination = [folder URLByAppendingPathComponent:item[@"name"]];
		[manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
		if (!error) {
			if ([item[@"text"] isKindOfClass:NSString.class])
				[item[@"text"] writeToURL:destination atomically:YES encoding:NSUTF8StringEncoding error:&error];
			else [manager copyItemAtURL:source toURL:destination error:&error];
		}
	}
	NSURL *archive = [temporary URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"zip"]];
	if (!error) {
		NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
		__block NSError *copyError = nil;
		[coordinator coordinateReadingItemAtURL:folder options:NSFileCoordinatorReadingForUploading error:&error
			byAccessor:^(NSURL *uploadURL) { [manager copyItemAtURL:uploadURL toURL:archive error:&copyError]; }];
		if (!error) error = copyError;
	}
	if (error) {
		[manager removeItemAtURL:temporary error:nil];
		lua_pushnil(L);
		lua_pushstring(L, error.localizedDescription.UTF8String);
		return 2;
	}
	UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[archive] applicationActivities:nil];
	activity.completionWithItemsHandler = ^(__unused UIActivityType type, __unused BOOL completed,
		__unused NSArray *returned, __unused NSError *activityError) {
		[manager removeItemAtURL:temporary error:nil];
	};
	UIPopoverPresentationController *popover = activity.popoverPresentationController;
	if (popover) {
		popover.sourceView = presenter.view;
		popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds),
			kActivityPopoverAnchorSide, kActivityPopoverAnchorSide);
		popover.permittedArrowDirections = 0;
	}
	[presenter presentViewController:activity animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
	lua_pushboolean(L, true);
	return 1;
}

// The native picker supplies temporary copies. Return only bounded UTF-8 text;
// projects never gain access to the host's filesystem or security-scoped URLs.
@interface LuaTextDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, strong) LuaReg *callback;
@end
@implementation LuaTextDocumentPickerDelegate
- (void)complete:(NSArray *)files error:(NSString *)error {
	lua_State *L = lua_reg_live_state(self.callback);
	if (L && lua_reg_push(self.callback)) {
		if (files) push_objc_value(L, files); else lua_pushnil(L);
		if (error) lua_pushstring(L, error.UTF8String); else lua_pushnil(L);
		lua_objc_pcall(L, 2, 0, "import text files");
	}
	[self.callback dispose];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (urls.count > kTextImportMaxFiles) { [self complete:nil error:@"Attach up to four text files"]; return; }
	NSMutableArray *files = [NSMutableArray array];
	for (NSURL *url in urls) {
		NSNumber *size = nil;
		[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
		if (!size || size.unsignedLongLongValue > kTextImportMaxBytes) {
			[self complete:nil error:@"Each attachment must be under 128 KB"]; return;
		}
		NSError *error = nil;
		NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
		if (!text) { [self complete:nil error:@"Choose UTF-8 text or source files"]; return; }
		[files addObject:@{@"name": url.lastPathComponent, @"text": text}];
	}
	[self complete:files error:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { [self complete:nil error:nil]; }
- (void)dealloc { [_callback dispose]; }
@end
static int bridge_UIKitPresentation_importTextFiles(lua_State *L) {
	LuaTextDocumentPickerDelegate *delegate = [LuaTextDocumentPickerDelegate new];
	delegate.callback = lua_reg_opt(L, 1);
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
		initForOpeningContentTypes:@[UTTypeText, UTTypeSourceCode, UTTypeData] asCopy:YES];
	picker.allowsMultipleSelection = YES;
	picker.delegate = delegate;
	objc_setAssociatedObject(picker, &kDocumentPickerDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	UIViewController *presenter = lua_uikit_presenter();
	if (!presenter) return luaL_error(L, "no UIKit presenter is installed");
	[presenter presentViewController:picker animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
	return 0;
}
