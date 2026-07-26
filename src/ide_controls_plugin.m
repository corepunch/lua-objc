#import <Cocoa/Cocoa.h>

#include <lua.h>
#include <lauxlib.h>

typedef struct {
	void *ptr;
} ObjCRef;

static int controls_color_well(lua_State *L) {
	NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
	ObjCRef *ref = lua_newuserdata(L, sizeof(ObjCRef));
	ref->ptr = (void *)CFBridgingRetain(well);
	luaL_setmetatable(L, "nsview");
	return 1;
}

static const luaL_Reg controls_lib[] = {
	{"ColorWell", controls_color_well},
	{NULL, NULL},
};

int luaopen_ide_controls(lua_State *L) {
	luaL_newlib(L, controls_lib);
	return 1;
}
