#pragma mark - Posted events

/* `_postEvent(fn)` runs `fn` later, from the main run loop's own event
 * routing, and costs nothing until then: no timer, no polling, so an idle app
 * uses no CPU. On the Mac it posts an application-defined NSEvent that a local
 * monitor receives in ordinary event dispatch; UIKit has no NSEvent queue and
 * uses the main dispatch queue, which wakes the run loop the same way. The
 * data layer (lua/data/events.lua) posts one event per burst of model changes
 * and rebinds the views of every model that changed. */

static NSMutableDictionary<NSNumber *, LuaReg *> *postedEvents;
static NSInteger nextPostedEvent;
static const short kPostedEventSubtype = 0x4C4F;

static void posted_event_run(NSInteger token) {
	NSNumber *key = @(token);
	LuaReg *reg = postedEvents[key];
	[postedEvents removeObjectForKey:key];
	lua_State *L = lua_reg_live_state(reg);
	if (L && lua_reg_push(reg)) lua_objc_pcall(L, 0, 0, "posted event");
	[reg dispose];
}

// _postEvent(fn)
static int bridge_post_event(lua_State *L) {
	luaL_checktype(L, 1, LUA_TFUNCTION);
	if (!postedEvents) postedEvents = [NSMutableDictionary dictionary];
	NSInteger token = ++nextPostedEvent;
	postedEvents[@(token)] = lua_reg_create(L, 1, NO);
#if TARGET_OS_OSX
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskApplicationDefined
			handler:^NSEvent *(NSEvent *event) {
			if (event.subtype != kPostedEventSubtype) return event;
			posted_event_run(event.data1);
			return nil;
		}];
	});
	[NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
		location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
		subtype:kPostedEventSubtype data1:token data2:0] atStart:NO];
#else
	dispatch_async(dispatch_get_main_queue(), ^{ posted_event_run(token); });
#endif
	return 0;
}

#define LUA_OBJC_EVENT_FUNCTIONS \
	{"_postEvent", bridge_post_event},
