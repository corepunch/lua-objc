/* lua_bridge_support.m — state-agnostic Lua/Foundation bridge helpers.
 *
 * This borrows LuaSkin's useful boundary patterns without adopting its global
 * state owner or general Objective-C object model. Platform roots define the
 * native view/window classes and metatable names before including this file.
 */

typedef struct {
	void *ptr;
} ObjCRef;

static const char *kHandleInternKey = "lua_objc.handles";

static void lua_objc_init_handles(lua_State *L) {
	lua_newtable(L);
	lua_newtable(L);
	lua_pushliteral(L, "v");
	lua_setfield(L, -2, "__mode");
	lua_setmetatable(L, -2);
	lua_setfield(L, LUA_REGISTRYINDEX, kHandleInternKey);
}

static int lua_objc_argerror_released(lua_State *L, int idx) {
	return luaL_argerror(L, idx, "native object has been released");
}

static int lua_objc_argerror_type(
	lua_State *L, int idx, const char *expectedName, const char *actualName
) {
	lua_pushfstring(L, "%s expected, got %s", expectedName, actualName);
	return luaL_argerror(L, idx, lua_tostring(L, -1));
}

static int lua_objc_conversion_error(lua_State *L, const char *tname) {
	return luaL_error(L, "cannot convert %s to a Foundation value", tname);
}

static id lua_objc_live_ptr(lua_State *L, int idx, ObjCRef *ref) {
	if (!ref || !ref->ptr) {
		lua_objc_argerror_released(L, idx);
		return nil;
	}
	return (__bridge id)ref->ptr;
}

static void push_objc(lua_State *L, id obj, const char *meta) {
	if (!obj) {
		lua_pushnil(L);
		return;
	}
	lua_getfield(L, LUA_REGISTRYINDEX, kHandleInternKey);
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		lua_objc_init_handles(L);
		lua_getfield(L, LUA_REGISTRYINDEX, kHandleInternKey);
	}
	lua_pushlightuserdata(L, (__bridge void *)obj);
	lua_rawget(L, -2);
	if (!lua_isnil(L, -1)) {
		lua_remove(L, -2);
		return;
	}
	lua_pop(L, 1);
	ObjCRef *ref = lua_newuserdata(L, sizeof(ObjCRef));
	ref->ptr = (void *)CFBridgingRetain(obj);
	luaL_setmetatable(L, meta);
	lua_pushlightuserdata(L, (__bridge void *)obj);
	lua_pushvalue(L, -2);
	lua_rawset(L, -4);
	lua_remove(L, -2);
}

#ifndef LUA_OBJC_VIEWCONTROLLER_METATABLE
#define LUA_OBJC_VIEWCONTROLLER_METATABLE "uiviewcontroller"
#endif

static ObjCRef *lua_objc_test_ref(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, LUA_OBJC_VIEW_METATABLE);
	if (!ref) ref = luaL_testudata(L, idx, LUA_OBJC_WINDOW_METATABLE);
	if (!ref) ref = luaL_testudata(L, idx, LUA_OBJC_VIEWCONTROLLER_METATABLE);
	if (!ref) ref = luaL_testudata(L, idx, "nsobject");
	return ref;
}

id lua_objc_check_object(
	lua_State *L,
	int idx,
	Class expectedClass,
	const char *expectedName
) {
	ObjCRef *ref = lua_objc_test_ref(L, idx);
	if (!ref) {
		luaL_typeerror(L, idx, expectedName);
		return nil;
	}
	id object = lua_objc_live_ptr(L, idx, ref);
	if (![object isKindOfClass:expectedClass]) {
		const char *got = class_getName([object class]);
		object = nil;
		lua_objc_argerror_type(L, idx, expectedName, got);
		return nil;
	}
	return object;
}

#define LUA_OBJC_CHECK_OBJECT(L, idx, type) \
	((type *)lua_objc_check_object((L), (idx), [type class], #type))

static int gc_objc(lua_State *L) {
	ObjCRef *ref = lua_touserdata(L, 1);
	if (ref && ref->ptr) {
		CFRelease(ref->ptr);
		ref->ptr = NULL;
	}
	return 0;
}

static int bridge_invalidate_handle(lua_State *L) {
	ObjCRef *ref = lua_objc_test_ref(L, 1);
	if (ref && ref->ptr) {
		CFRelease(ref->ptr);
		ref->ptr = NULL;
	}
	return 0;
}

static BOOL lua_objc_number_is_boolean(NSNumber *number) {
	return CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID();
}

static BOOL lua_objc_number_is_integer(NSNumber *number) {
	const char *type = number.objCType;
	return strchr("cCsSiIlLqQ", type[0]) != NULL && type[1] == '\0';
}

static void lua_objc_push_foundation_value(
	lua_State *L,
	id value,
	NSHashTable *ancestors,
	NSUInteger depth
) {
	if (!value || value == [NSNull null]) {
		lua_pushnil(L);
		return;
	}
	if ([value isKindOfClass:[NSString class]]) {
		NSData *utf8 = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
		lua_pushlstring(L, utf8.bytes, utf8.length);
		return;
	}
	if ([value isKindOfClass:[NSData class]]) {
		NSData *data = (NSData *)value;
		lua_pushlstring(L, data.bytes, data.length);
		return;
	}
	if ([value isKindOfClass:[NSNumber class]]) {
		NSNumber *number = (NSNumber *)value;
		if (lua_objc_number_is_boolean(number)) {
			lua_pushboolean(L, number.boolValue);
		} else if (lua_objc_number_is_integer(number)) {
			lua_pushinteger(L, (lua_Integer)number.longLongValue);
		} else {
			lua_pushnumber(L, number.doubleValue);
		}
		return;
	}
	if (depth >= 64 || [ancestors containsObject:value]) {
		lua_pushnil(L);
		return;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		[ancestors addObject:value];
		lua_createtable(L, (int)[(NSArray *)value count], 0);
		[(NSArray *)value enumerateObjectsUsingBlock:^(id item, NSUInteger idx, BOOL *stop) {
			lua_objc_push_foundation_value(L, item, ancestors, depth + 1);
			lua_rawseti(L, -2, (lua_Integer)idx + 1);
		}];
		[ancestors removeObject:value];
		return;
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		[ancestors addObject:value];
		lua_createtable(L, 0, (int)[(NSDictionary *)value count]);
		for (id key in (NSDictionary *)value) {
			lua_objc_push_foundation_value(L, key, ancestors, depth + 1);
			if (lua_isnil(L, -1)) {
				lua_pop(L, 1);
				continue;
			}
			lua_objc_push_foundation_value(
				L, [(NSDictionary *)value objectForKey:key], ancestors, depth + 1);
			lua_settable(L, -3);
		}
		[ancestors removeObject:value];
		return;
	}
	if ([value isKindOfClass:[LUA_OBJC_VIEW_CLASS class]]) {
		push_objc(L, value, LUA_OBJC_VIEW_METATABLE);
		return;
	}
	if ([value isKindOfClass:[LUA_OBJC_WINDOW_CLASS class]]) {
		push_objc(L, value, LUA_OBJC_WINDOW_METATABLE);
		return;
	}
	push_objc(L, value, "nsobject");
}

static void push_objc_value(lua_State *L, id value) {
	NSHashTable *ancestors =
		[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	lua_objc_push_foundation_value(L, value, ancestors, 0);
}

static id lua_objc_foundation_value_at_index(
	lua_State *L,
	int idx,
	NSMutableSet<NSValue *> *ancestors,
	NSUInteger depth,
	BOOL *converted
) {
	idx = lua_absindex(L, idx);
	switch (lua_type(L, idx)) {
		case LUA_TNIL:
			*converted = YES;
			return nil;
		case LUA_TBOOLEAN:
			*converted = YES;
			return @((BOOL)lua_toboolean(L, idx));
		case LUA_TNUMBER:
			*converted = YES;
			return lua_isinteger(L, idx)
				? @((long long)lua_tointeger(L, idx))
				: @(lua_tonumber(L, idx));
		case LUA_TSTRING: {
			size_t length = 0;
			const char *bytes = lua_tolstring(L, idx, &length);
			NSString *string = [[NSString alloc] initWithBytes:bytes
				length:length encoding:NSUTF8StringEncoding];
			*converted = string != nil;
			return string;
		}
		case LUA_TUSERDATA: {
			ObjCRef *ref = lua_objc_test_ref(L, idx);
			*converted = ref != NULL;
			return ref ? (__bridge id)ref->ptr : nil;
		}
		case LUA_TTABLE: {
			if (depth >= 64) {
				*converted = NO;
				return nil;
			}
			NSValue *identity =
				[NSValue valueWithPointer:lua_topointer(L, idx)];
			if ([ancestors containsObject:identity]) {
				*converted = NO;
				return nil;
			}
			[ancestors addObject:identity];

			lua_Integer count = (lua_Integer)lua_rawlen(L, idx);
			BOOL array = YES;
			lua_Integer entries = 0;
			lua_pushnil(L);
			while (lua_next(L, idx) != 0) {
				entries++;
				if (!lua_isinteger(L, -2)) {
					array = NO;
				} else {
					lua_Integer key = lua_tointeger(L, -2);
					if (key < 1 || key > count) array = NO;
				}
				lua_pop(L, 1);
			}
			array = array && entries == count;

			id result = nil;
			BOOL childrenConverted = YES;
			if (array) {
				NSMutableArray *values =
					[NSMutableArray arrayWithCapacity:(NSUInteger)count];
				for (lua_Integer i = 1; i <= count; i++) {
					lua_rawgeti(L, idx, i);
					BOOL childConverted = NO;
					id child = lua_objc_foundation_value_at_index(
						L, -1, ancestors, depth + 1, &childConverted);
					lua_pop(L, 1);
					if (!childConverted) {
						childrenConverted = NO;
						break;
					}
					[values addObject:child ?: [NSNull null]];
				}
				if (childrenConverted) result = values;
			} else {
				NSMutableDictionary *values = [NSMutableDictionary dictionary];
				lua_pushnil(L);
				while (lua_next(L, idx) != 0) {
					BOOL keyConverted = NO;
					BOOL valueConverted = NO;
					id key = lua_objc_foundation_value_at_index(
						L, -2, ancestors, depth + 1, &keyConverted);
					id value = lua_objc_foundation_value_at_index(
						L, -1, ancestors, depth + 1, &valueConverted);
					lua_pop(L, 1);
					if (!keyConverted || !valueConverted
						|| ![key conformsToProtocol:@protocol(NSCopying)]) {
						childrenConverted = NO;
						break;
					}
					values[key] = value ?: [NSNull null];
				}
				if (!childrenConverted) lua_pop(L, 1);
				if (childrenConverted) result = values;
			}
			[ancestors removeObject:identity];
			*converted = childrenConverted;
			return result;
		}
		default:
			*converted = NO;
			return nil;
	}
}

static id lua_to_objc_value(lua_State *L, int idx) {
	BOOL converted = NO;
	const char *tname = NULL;
	id value = nil;
	{
		NSMutableSet<NSValue *> *ancestors = [NSMutableSet set];
		value = lua_objc_foundation_value_at_index(
			L, idx, ancestors, 0, &converted);
		if (!converted) tname = luaL_typename(L, idx);
		ancestors = nil;
		if (converted) return value;
		value = nil;
	}
	lua_objc_conversion_error(L, tname);
	return nil;
}
