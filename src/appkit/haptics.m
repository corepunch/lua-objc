static int bridge_haptics_available(lua_State *L) {
	lua_pushboolean(L, NSHapticFeedbackManager.defaultPerformer != nil);
	return 1;
}

static int bridge_reduce_motion_enabled(lua_State *L) {
	lua_pushboolean(L, NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion);
	return 1;
}

static int bridge_haptic_impact(lua_State *L) {
	(void)luaL_optstring(L, 1, "medium");
	[NSHapticFeedbackManager.defaultPerformer
		performFeedbackPattern:NSHapticFeedbackPatternGeneric
		performanceTime:NSHapticFeedbackPerformanceTimeNow];
	return 0;
}

static int bridge_haptic_selection(lua_State *L) {
	[NSHapticFeedbackManager.defaultPerformer
		performFeedbackPattern:NSHapticFeedbackPatternLevelChange
		performanceTime:NSHapticFeedbackPerformanceTimeNow];
	return 0;
}

static int bridge_haptic_notification(lua_State *L) {
	const char *kind = luaL_optstring(L, 1, "success");
	NSHapticFeedbackPattern pattern = strcmp(kind, "success") == 0
		? NSHapticFeedbackPatternLevelChange : NSHapticFeedbackPatternGeneric;
	[NSHapticFeedbackManager.defaultPerformer
		performFeedbackPattern:pattern
		performanceTime:NSHapticFeedbackPerformanceTimeNow];
	return 0;
}
