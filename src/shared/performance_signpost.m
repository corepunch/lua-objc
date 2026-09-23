#import <os/log.h>
#import <os/signpost.h>

static os_log_t lua_objc_performance_log(void) {
	static os_log_t log;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		log = os_log_create("org.luaobjc", "Performance");
	});
	return log;
}

#define LUA_OBJC_PERF_BEGIN(name, identifier) \
	os_signpost_id_t identifier = os_signpost_id_generate(lua_objc_performance_log()); \
	os_signpost_interval_begin(lua_objc_performance_log(), identifier, name)
#define LUA_OBJC_PERF_END(name, identifier) \
	os_signpost_interval_end(lua_objc_performance_log(), identifier, name)
