#pragma mark - Paragraph (shared by AppKit and UIKit)

/* Long-form prose set as a book sets it, on TextKit 1 on both platforms (see
 * appkit/paragraph.m and uikit/paragraph.m for the views). What does not
 * depend on the view class lives here: the revealed prefix, link ranges and
 * styling, the body's attributes, the figure's size and the bridge for
 * links. */

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

/* What each platform's paragraph view provides to the shared code below. */
@protocol LuaParagraphText <NSObject>
@property(nonatomic, readonly, copy) NSString *paragraphText;
/* Characters shown so far, counted as Lua's utf8.len counts them; -1 shows
 * the whole paragraph. */
@property(nonatomic, readonly) NSInteger revealedCharacters;
@property(nonatomic, copy) NSArray<LuaParagraphLink *> *links;
@property(nonatomic, readonly) NSTextStorage *textStorage;
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

/* Links are ruled with a thicker dotted line, dropped a little below the
 * baseline so it clears descenders. */
@interface LuaParagraphLayoutManager : NSLayoutManager
@end

@implementation LuaParagraphLayoutManager
- (void)drawUnderlineForGlyphRange:(NSRange)glyphRange underlineType:(NSUnderlineStyle)underlineVal
		baselineOffset:(CGFloat)baselineOffset lineFragmentRect:(CGRect)lineRect
		lineFragmentGlyphRange:(NSRange)lineGlyphRange containerOrigin:(CGPoint)containerOrigin {
	[super drawUnderlineForGlyphRange:glyphRange underlineType:underlineVal
		baselineOffset:baselineOffset + kParagraphLinkUnderlineOffset lineFragmentRect:lineRect
		lineFragmentGlyphRange:lineGlyphRange containerOrigin:containerOrigin];
}
@end

/* The UTF-16 length of the revealed prefix of `text`, never splitting a
 * composed character or surrogate pair. */
static NSUInteger paragraph_revealed_length(NSString *text, NSInteger scalars) {
	if (scalars < 0) return text.length;
	NSUInteger offset = 0;
	for (; scalars > 0 && offset < text.length; scalars--)
		offset += CFStringIsSurrogateHighCharacter([text characterAtIndex:offset]) && offset + 1 < text.length ? 2 : 1;
	if (offset > 0 && offset < text.length)
		offset = NSMaxRange([text rangeOfComposedCharacterSequenceAtIndex:offset - 1]);
	return offset;
}

static NSUInteger paragraph_shown_length(id<LuaParagraphText> view) {
	return MIN(paragraph_revealed_length(view.paragraphText, view.revealedCharacters), view.textStorage.length);
}

/* A link's range in the text storage; its location is NSNotFound when none
 * of the link is in the storage. */
static NSRange paragraph_link_range(id<LuaParagraphText> view, LuaParagraphLink *link) {
	NSString *text = view.paragraphText;
	NSUInteger start = paragraph_revealed_length(text, MAX(0, link.location));
	NSUInteger end = paragraph_revealed_length(text, MAX(0, link.location) + MAX(0, link.length));
	end = MIN(end, view.textStorage.length);
	return start < end ? NSMakeRange(start, end - start) : NSMakeRange(NSNotFound, 0);
}

/* The link, if any, whose revealed words include the storage's character. */
static LuaParagraphLink *paragraph_link_at(id<LuaParagraphText> view, NSUInteger index) {
	if (index >= paragraph_shown_length(view)) return nil;
	for (LuaParagraphLink *link in view.links)
		if (NSLocationInRange(index, paragraph_link_range(view, link))) return link;
	return nil;
}

/* Rules every link. `clickable` also marks it as a text link, numbered by
 * its place, for a view that reports link clicks (NSTextView). */
static void paragraph_apply_links(id<LuaParagraphText> view, BOOL clickable) {
	NSTextStorage *storage = view.textStorage;
	[storage beginEditing];
	[view.links enumerateObjectsUsingBlock:^(LuaParagraphLink *link, NSUInteger index, __unused BOOL *stop) {
		NSRange range = paragraph_link_range(view, link);
		if (range.location == NSNotFound) return;
		if (clickable) [storage addAttribute:NSLinkAttributeName value:@(index).stringValue range:range];
		[storage addAttribute:NSUnderlineStyleAttributeName
			value:@(NSUnderlineStyleThick | NSUnderlineStylePatternDot) range:range];
	}];
	[storage endEditing];
}

/* Inks the revealed prefix in `body` and hides the rest in `clear`; a link
 * is set in `ink` and ruled only under the words typed so far. */
static void paragraph_apply_reveal(id<LuaParagraphText> view, id body, id ink, id clear) {
	NSTextStorage *storage = view.textStorage;
	NSUInteger shown = paragraph_shown_length(view);
	[storage beginEditing];
	[storage addAttribute:NSForegroundColorAttributeName value:body range:NSMakeRange(0, shown)];
	[storage addAttribute:NSForegroundColorAttributeName value:clear range:NSMakeRange(shown, storage.length - shown)];
	for (LuaParagraphLink *link in view.links) {
		NSRange range = paragraph_link_range(view, link);
		if (range.location == NSNotFound) continue;
		NSRange visible = NSIntersectionRange(range, NSMakeRange(0, shown));
		[storage addAttribute:NSUnderlineColorAttributeName value:clear range:range];
		if (!visible.length) continue;
		[storage addAttribute:NSForegroundColorAttributeName value:ink range:visible];
		[storage addAttribute:NSUnderlineColorAttributeName value:ink range:visible];
	}
	[storage endEditing];
}

/* The body's attributes. A positive `lineHeight` fixes every line to it, so
 * the lines beside the figure keep the pitch the figure was sized for. */
static NSAttributedString *paragraph_body_string(NSString *text, id font, id color, CGFloat lineSpacing,
	NSTextAlignment alignment, BOOL hyphenation, CGFloat lineHeight) {
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.lineSpacing = lineSpacing;
	style.alignment = alignment;
	style.hyphenationFactor = hyphenation ? 1.0 : 0.0;
	if (lineHeight > 0) style.minimumLineHeight = style.maximumLineHeight = lineHeight;
	return [[NSAttributedString alloc] initWithString:text attributes:@{
		NSFontAttributeName: font,
		NSForegroundColorAttributeName: color,
		NSParagraphStyleAttributeName: style,
	}];
}

/* The figure spans exactly `lines` lines, from the first line's top to the
 * last line's bottom, and is as wide as it is tall. Lines beside it keep a
 * gap from it; the next line returns to the margin. */
static CGFloat paragraph_figure_side(NSInteger lines, CGFloat lineHeight, CGFloat lineSpacing) {
	return lines * (lineHeight + lineSpacing) - lineSpacing;
}

static CGRect paragraph_figure_exclusion(CGFloat side, CGFloat lineSpacing) {
	return CGRectMake(0, 0, side + kParagraphFigureGap, side + lineSpacing / 2);
}

static id<LuaParagraphText> paragraph_check(lua_State *L, int index) {
	id view = check_objc(L, index);
	if (![view conformsToProtocol:@protocol(LuaParagraphText)]) luaL_error(L, "expected a Paragraph");
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
	id<LuaParagraphText> view = paragraph_check(L, 1);
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
	id<LuaParagraphText> view = paragraph_check(L, 1);
	lua_newtable(L);
	[view.links enumerateObjectsUsingBlock:^(LuaParagraphLink *link, NSUInteger index, __unused BOOL *stop) {
		lua_newtable(L);
		lua_pushinteger(L, link.location); lua_setfield(L, -2, "location");
		lua_pushinteger(L, link.length); lua_setfield(L, -2, "length");
		lua_pushstring(L, link.label.UTF8String); lua_setfield(L, -2, "label");
		NSRange range = paragraph_link_range(view, link);
		lua_pushstring(L, range.location == NSNotFound ? ""
			: [view.textStorage.string substringWithRange:range].UTF8String);
		lua_setfield(L, -2, "text");
		BOOL revealed = range.location != NSNotFound && paragraph_link_at(view, range.location) == link;
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
	id<LuaParagraphText> view = paragraph_check(L, 1);
	lua_Integer link = luaL_checkinteger(L, 2), item = luaL_checkinteger(L, 3);
	if (link < 1 || link > (lua_Integer)view.links.count) return luaL_error(L, "no such paragraph link");
	LuaParagraphLink *target = view.links[(NSUInteger)link - 1];
	if (item < 1 || item > (lua_Integer)target.titles.count) return luaL_error(L, "no such link item");
	[target performItem:(NSUInteger)item - 1];
	return 0;
}
