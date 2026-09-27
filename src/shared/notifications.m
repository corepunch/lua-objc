#pragma mark - User notifications (UNUserNotificationCenter)

/* Local notifications for reminders and watchers. The notification center
 * belongs to an app bundle: a process without a bundle identifier (the
 * development runtime, headless tests) has none, and the API reports that
 * instead of crashing. A notification's `onResponse` runs when the person
 * clicks it or its action button; the callback lives until the notification
 * is removed or replaced. */
#import <UserNotifications/UserNotifications.h>

static NSMutableDictionary<NSString *, LuaReg *> *notificationResponses;

@interface LuaNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

static void notification_respond(NSString *identifier, NSString *action) {
	LuaReg *reg = notificationResponses[identifier];
	lua_State *L = lua_reg_live_state(reg);
	if (!L || !lua_reg_push(reg)) return;
	lua_pushstring(L, identifier.UTF8String);
	lua_pushstring(L, action.UTF8String);
	lua_objc_pcall(L, 2, 0, "notification response");
}

@implementation LuaNotificationDelegate
// Shown even while the app is frontmost, as a banner.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
	withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
	(void)center; (void)notification;
	completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
	withCompletionHandler:(void (^)(void))completionHandler {
	(void)center;
	NSString *identifier = response.notification.request.identifier;
	NSString *action = [response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier] ? @"open" : response.actionIdentifier;
	dispatch_async(dispatch_get_main_queue(), ^{ notification_respond(identifier, action); });
	completionHandler();
}
@end

static BOOL notifications_available(void) {
	return NSBundle.mainBundle.bundleIdentifier.length > 0;
}

static UNUserNotificationCenter *notification_center(void) {
	static LuaNotificationDelegate *delegate;
	if (!notifications_available()) return nil;
	UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
	if (!delegate) { delegate = [LuaNotificationDelegate new]; center.delegate = delegate; }
	return center;
}

static int bridge_notifications_available(lua_State *L) {
	lua_pushboolean(L, notifications_available());
	return 1;
}

// _requestNotifications(callback(granted, message))
static int bridge_request_notifications(lua_State *L) {
	LuaReg *reg = lua_reg_create(L, 1, NO);
	UNUserNotificationCenter *center = notification_center();
	void (^finish)(BOOL, NSString *) = ^(BOOL granted, NSString *message) {
		dispatch_async(dispatch_get_main_queue(), ^{
			lua_State *state = lua_reg_live_state(reg);
			if (state && lua_reg_push(reg)) {
				lua_pushboolean(state, granted);
				if (message) lua_pushstring(state, message.UTF8String); else lua_pushnil(state);
				lua_objc_pcall(state, 2, 0, "notification authorization");
			}
			[reg dispose];
		});
	};
	if (!center) { finish(NO, @"Notifications need the app bundle."); return 0; }
	[center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
		completionHandler:^(BOOL granted, NSError *error) { finish(granted, error.localizedDescription); }];
	return 0;
}

static NSString *notification_string(lua_State *L, int idx, const char *name) {
	lua_getfield(L, idx, name);
	NSString *value = lua_isstring(L, -1) ? [NSString stringWithUTF8String:lua_tostring(L, -1)] : nil;
	lua_pop(L, 1);
	return value;
}

// _notify({id, title, subtitle, body, action, delay, day, hour, minute,
// repeats}, onResponse) -> posted. `delay` posts after seconds; `day`/`hour`
// schedule on a calendar date (monthly when only `day` is fixed and
// `repeats` is true); neither posts now. The same id replaces a pending one.
static int bridge_notify(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSString *identifier = notification_string(L, 1, "id");
	if (!identifier.length) return luaL_error(L, "a notification requires an id");
	UNUserNotificationCenter *center = notification_center();
	if (!center) { lua_pushboolean(L, 0); return 1; }
	UNMutableNotificationContent *content = [UNMutableNotificationContent new];
	content.title = notification_string(L, 1, "title") ?: @"";
	content.subtitle = notification_string(L, 1, "subtitle") ?: @"";
	content.body = notification_string(L, 1, "body") ?: @"";
	content.sound = UNNotificationSound.defaultSound;
	NSString *action = notification_string(L, 1, "action");
	if (action.length) {
		NSString *category = [@"lua." stringByAppendingString:identifier];
		UNNotificationAction *button = [UNNotificationAction actionWithIdentifier:@"action" title:action
			options:UNNotificationActionOptionForeground];
		UNNotificationCategory *entry = [UNNotificationCategory categoryWithIdentifier:category actions:@[button]
			intentIdentifiers:@[] options:0];
		[center getNotificationCategoriesWithCompletionHandler:^(NSSet<UNNotificationCategory *> *existing) {
			NSMutableSet *categories = [NSMutableSet set];
			for (UNNotificationCategory *other in existing) if (![other.identifier isEqualToString:category]) [categories addObject:other];
			[categories addObject:entry];
			[center setNotificationCategories:categories];
		}];
		content.categoryIdentifier = category;
	}
	UNNotificationTrigger *trigger = nil;
	lua_getfield(L, 1, "delay");
	if (lua_isnumber(L, -1) && lua_tonumber(L, -1) > 0)
		trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:lua_tonumber(L, -1) repeats:NO];
	lua_pop(L, 1);
	lua_getfield(L, 1, "day");
	if (lua_isnumber(L, -1)) {
		NSDateComponents *date = [NSDateComponents new];
		date.day = (NSInteger)lua_tointeger(L, -1);
		lua_getfield(L, 1, "hour"); date.hour = lua_isnumber(L, -1) ? (NSInteger)lua_tointeger(L, -1) : 10; lua_pop(L, 1);
		lua_getfield(L, 1, "minute"); date.minute = lua_isnumber(L, -1) ? (NSInteger)lua_tointeger(L, -1) : 0; lua_pop(L, 1);
		lua_getfield(L, 1, "repeats"); BOOL repeats = lua_toboolean(L, -1); lua_pop(L, 1);
		trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:date repeats:repeats];
	}
	lua_pop(L, 1);
	if (!notificationResponses) notificationResponses = [NSMutableDictionary dictionary];
	[notificationResponses[identifier] dispose];
	notificationResponses[identifier] = lua_isfunction(L, 2) ? lua_reg_create(L, 2, NO) : nil;
	[center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger]
		withCompletionHandler:nil];
	lua_pushboolean(L, 1);
	return 1;
}

// _removeNotification(id): withdraws a pending or delivered notification.
static int bridge_remove_notification(lua_State *L) {
	NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	[notificationResponses[identifier] dispose];
	[notificationResponses removeObjectForKey:identifier];
	UNUserNotificationCenter *center = notification_center();
	[center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
	[center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
	return 0;
}

// Test hook: _notificationRespond(id, action) as if the person clicked it.
static int bridge_notification_respond(lua_State *L) {
	notification_respond([NSString stringWithUTF8String:luaL_checkstring(L, 1)],
		[NSString stringWithUTF8String:luaL_optstring(L, 2, "open")]);
	return 0;
}

// Test hook: registers a response without posting, where no bundle exists.
static int bridge_notification_register(lua_State *L) {
	NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	if (!notificationResponses) notificationResponses = [NSMutableDictionary dictionary];
	[notificationResponses[identifier] dispose];
	notificationResponses[identifier] = lua_reg_create(L, 2, NO);
	return 0;
}

#define LUA_OBJC_NOTIFICATION_FUNCTIONS \
	{"_notificationsAvailable", bridge_notifications_available}, \
	{"_requestNotifications", bridge_request_notifications}, \
	{"_notify", bridge_notify}, \
	{"_removeNotification", bridge_remove_notification}, \
	{"_notificationRespond", bridge_notification_respond}, \
	{"_notificationRegister", bridge_notification_register},
