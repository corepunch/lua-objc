#pragma mark - Paragraph links

/* A run of the paragraph the reader can act on: tapping it opens a menu of
 * what can be done with the thing the words name. `location` and `length`
 * count characters as Lua's utf8.len does, like `revealedCharacters`. */
@interface LuaParagraphLink : NSObject
@property(nonatomic) NSInteger location;
@property(nonatomic) NSInteger length;
@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) NSArray<NSString *> *titles;
@property(nonatomic, copy) NSArray<NSString *> *symbols;
/* A LuaReg for each item, or NSNull for an item without an action. */
@property(nonatomic, copy) NSArray *callbacks;
- (void)performItem:(NSUInteger)index;
@end

/* What each platform's paragraph view provides to the bridge below. */
@protocol LuaParagraphLinking <NSObject>
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
@property(nonatomic, readonly) NSTextStorage *textStorage;
/* A link's range in the text storage, which leaves out a dropped initial;
 * its location is NSNotFound when none of the link is in the storage. */
- (NSRange)bodyRangeOfLink:(LuaParagraphLink *)link;
/* The link, if any, whose revealed words include the storage's character. */
- (LuaParagraphLink *)linkAtCharacterIndex:(NSUInteger)index;
@end

@implementation LuaParagraphLink
- (void)performItem:(NSUInteger)index {
	if (index >= self.callbacks.count) return;
	id callback = self.callbacks[index];
	if (![callback isKindOfClass:LuaReg.class]) return;
	lua_State *L = lua_reg_live_state(callback);
	if (L && lua_reg_push(callback)) lua_objc_pcall(L, 0, 0, "paragraph link");
}
- (void)dealloc {
	for (id callback in _callbacks)
		if ([callback isKindOfClass:LuaReg.class]) [callback dispose];
}
@end

static id<LuaParagraphLinking> paragraph_check(lua_State *L, int index) {
	id view = check_objc(L, index);
	if (![view conformsToProtocol:@protocol(LuaParagraphLinking)]) luaL_error(L, "expected a Paragraph");
	return view;
}

static NSString *paragraph_string_field(lua_State *L, int index, const char *name) {
	lua_getfield(L, index, name);
	NSString *value = lua_isstring(L, -1) ? @(lua_tostring(L, -1)) : @"";
	lua_pop(L, 1);
	return value;
}

/* _paragraphSetLinks(view, { { location, length, label, items = { { title,
 * systemImage, action }, … } }, … }) */
static int bridge_paragraph_set_links(lua_State *L) {
	id<LuaParagraphLinking> view = paragraph_check(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	NSMutableArray<LuaParagraphLink *> *links = [NSMutableArray array];
	lua_Integer count = luaL_len(L, 2);
	for (lua_Integer i = 1; i <= count; i++) {
		lua_rawgeti(L, 2, i);
		int entry = lua_gettop(L);
		luaL_checktype(L, entry, LUA_TTABLE);
		LuaParagraphLink *link = [[LuaParagraphLink alloc] init];
		lua_getfield(L, entry, "location");
		link.location = (NSInteger)luaL_optinteger(L, -1, 0);
		lua_getfield(L, entry, "length");
		link.length = (NSInteger)luaL_optinteger(L, -1, 0);
		lua_pop(L, 2);
		link.label = paragraph_string_field(L, entry, "label");
		NSMutableArray *titles = [NSMutableArray array], *symbols = [NSMutableArray array],
			*callbacks = [NSMutableArray array];
		lua_getfield(L, entry, "items");
		if (lua_istable(L, -1)) {
			int items = lua_gettop(L);
			lua_Integer itemCount = luaL_len(L, items);
			for (lua_Integer j = 1; j <= itemCount; j++) {
				lua_rawgeti(L, items, j);
				[titles addObject:paragraph_string_field(L, -1, "title")];
				[symbols addObject:paragraph_string_field(L, -1, "systemImage")];
				lua_getfield(L, -1, "action");
				[callbacks addObject:lua_reg_opt(L, -1) ?: NSNull.null];
				lua_pop(L, 2);
			}
		}
		lua_pop(L, 1);
		link.titles = titles;
		link.symbols = symbols;
		link.callbacks = callbacks;
		[links addObject:link];
		lua_pop(L, 1);
	}
	view.links = links;
	return 0;
}

/* _paragraphLinks(view) → { { location, length, label, text, revealed,
 * inked, titles }, … }, where `text` is the linked words as the text storage
 * holds them and `inked` says revealed words are set in their rule's colour. */
static int bridge_paragraph_links(lua_State *L) {
	id<LuaParagraphLinking> view = paragraph_check(L, 1);
	lua_newtable(L);
	[view.links enumerateObjectsUsingBlock:^(LuaParagraphLink *link, NSUInteger index, __unused BOOL *stop) {
		lua_newtable(L);
		lua_pushinteger(L, link.location); lua_setfield(L, -2, "location");
		lua_pushinteger(L, link.length); lua_setfield(L, -2, "length");
		lua_pushstring(L, link.label.UTF8String); lua_setfield(L, -2, "label");
		NSRange range = [view bodyRangeOfLink:link];
		lua_pushstring(L, range.location == NSNotFound ? ""
			: [view.textStorage.string substringWithRange:range].UTF8String);
		lua_setfield(L, -2, "text");
		BOOL revealed = range.location != NSNotFound && [view linkAtCharacterIndex:range.location] == link;
		lua_pushboolean(L, revealed);
		lua_setfield(L, -2, "revealed");
		NSDictionary *attributes = revealed
			? [view.textStorage attributesAtIndex:range.location effectiveRange:NULL] : nil;
		id rule = attributes[NSUnderlineColorAttributeName];
		lua_pushboolean(L, rule && [attributes[NSForegroundColorAttributeName] isEqual:rule]);
		lua_setfield(L, -2, "inked");
		lua_newtable(L);
		[link.titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger item, __unused BOOL *inner) {
			lua_pushstring(L, title.UTF8String);
			lua_rawseti(L, -2, (lua_Integer)item + 1);
		}];
		lua_setfield(L, -2, "titles");
		lua_rawseti(L, -2, (lua_Integer)index + 1);
	}];
	return 1;
}

/* _paragraphPerformLink(view, link, item): chooses a menu item as a tap does. */
static int bridge_paragraph_perform_link(lua_State *L) {
	id<LuaParagraphLinking> view = paragraph_check(L, 1);
	lua_Integer link = luaL_checkinteger(L, 2), item = luaL_checkinteger(L, 3);
	if (link < 1 || link > (lua_Integer)view.links.count) return luaL_error(L, "no such paragraph link");
	LuaParagraphLink *target = view.links[(NSUInteger)link - 1];
	if (item < 1 || item > (lua_Integer)target.titles.count) return luaL_error(L, "no such link item");
	[target performItem:(NSUInteger)item - 1];
	return 0;
}
