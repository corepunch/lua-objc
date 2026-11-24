#pragma mark - Paragraph (shared by AppKit and UIKit)

/* Long-form prose set as a book sets it, on TextKit 1 on both platforms (see
 * appkit/paragraph.m and uikit/paragraph.m for the views). What does not
 * depend on the view class lives here: the revealed prefix, link ranges and
 * styling, the body's attributes and the bridge for links. */

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
@property(nonatomic, copy) NSArray<NSDictionary *> *boldRanges;
@property(nonatomic, copy) NSArray<NSDictionary *> *italicRanges;
@property(nonatomic, readonly) NSTextStorage *textStorage;
@property(nonatomic, readonly) id paragraphLinkColor;
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

/* Bold every link in the body's font family. `clickable` also marks it as a text link, numbered by
 * its place, for a view that reports link clicks (NSTextView). */
static void paragraph_bold_range(NSTextStorage *storage, NSRange range) {
	if (range.location == NSNotFound || !range.length) return;
#if TARGET_OS_IPHONE
	UIFont *font = [storage attribute:NSFontAttributeName atIndex:range.location effectiveRange:NULL];
	UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorWithSymbolicTraits:
		(font.fontDescriptor.symbolicTraits | UIFontDescriptorTraitBold)];
	id bold = descriptor ? [UIFont fontWithDescriptor:descriptor size:font.pointSize] : font;
#else
	NSFont *font = [storage attribute:NSFontAttributeName atIndex:range.location effectiveRange:NULL];
	id bold = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
#endif
	if (bold) [storage addAttribute:NSFontAttributeName value:bold range:range];
}

/* Formatting ranges use ordinary KVC data; they carry no link or action. */
static NSRange paragraph_bold_range_for(id<LuaParagraphText> view, NSDictionary *record) {
	NSInteger location = [record[@"location"] integerValue], length = [record[@"length"] integerValue];
	if (location < 0 || length <= 0) return NSMakeRange(NSNotFound, 0);
	NSUInteger start = paragraph_revealed_length(view.paragraphText, location);
	NSUInteger end = paragraph_revealed_length(view.paragraphText, location + length);
	end = MIN(end, view.textStorage.length);
	return start < end ? NSMakeRange(start, end - start) : NSMakeRange(NSNotFound, 0);
}

static void paragraph_italic_range(NSTextStorage *storage, NSRange range) {
	if (range.location == NSNotFound || !range.length) return;
	[storage enumerateAttribute:NSFontAttributeName inRange:range options:0 usingBlock:^(id font, NSRange run, __unused BOOL *stop) {
#if TARGET_OS_IPHONE
		UIFontDescriptor *descriptor = [((UIFont *)font).fontDescriptor fontDescriptorWithSymbolicTraits:
			(((UIFont *)font).fontDescriptor.symbolicTraits | UIFontDescriptorTraitItalic)];
		id italic = descriptor ? [UIFont fontWithDescriptor:descriptor size:((UIFont *)font).pointSize] : font;
#else
		id italic = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask];
#endif
		if (italic) [storage addAttribute:NSFontAttributeName value:italic range:run];
	}];
}

static void paragraph_apply_links(id<LuaParagraphText> view, BOOL clickable) {
	NSTextStorage *storage = view.textStorage;
	[storage beginEditing];
	for (NSDictionary *record in view.boldRanges)
		paragraph_bold_range(storage, paragraph_bold_range_for(view, record));
	[view.links enumerateObjectsUsingBlock:^(LuaParagraphLink *link, NSUInteger index, __unused BOOL *stop) {
		NSRange range = paragraph_link_range(view, link);
		if (range.location == NSNotFound) return;
		if (clickable) [storage addAttribute:NSLinkAttributeName value:@(index).stringValue range:range];
		paragraph_bold_range(storage, range);
	}];
	for (NSDictionary *record in view.italicRanges)
		paragraph_italic_range(storage, paragraph_bold_range_for(view, record));
	[storage endEditing];
}

/* Inks the revealed prefix in `body` and hides the rest in `clear`; visible
 * linked words use `ink`. */
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
		if (!visible.length) continue;
		[storage addAttribute:NSForegroundColorAttributeName value:ink range:visible];
	}
	[storage endEditing];
}

/* The body's attributes. A positive `lineHeight` keeps a consistent baseline pitch. */
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
 * holds them and `inked` says revealed words use the link colour. */
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
		lua_pushboolean(L, revealed && [attributes[NSForegroundColorAttributeName] isEqual:view.paragraphLinkColor]);
		lua_setfield(L, -2, "inked");
#if TARGET_OS_IPHONE
		UIFont *font = attributes[NSFontAttributeName];
		BOOL bold = (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
#else
		NSFont *font = attributes[NSFontAttributeName];
		BOOL bold = font && ([[NSFontManager sharedFontManager] traitsOfFont:font] & NSBoldFontMask) != 0;
#endif
		lua_pushboolean(L, bold); lua_setfield(L, -2, "bold");
		lua_pushboolean(L, [attributes[NSUnderlineStyleAttributeName] integerValue] != 0);
		lua_setfield(L, -2, "underlined");
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

/* Test-only inspection of the actual TextKit attributes at a scalar offset. */
static int bridge_paragraph_attributes(lua_State *L) {
	id<LuaParagraphText> view = paragraph_check(L, 1);
	NSInteger offset = luaL_checkinteger(L, 2);
	NSUInteger index = paragraph_revealed_length(view.paragraphText, MAX(0, offset));
	NSDictionary *attributes = offset >= 0 && index < view.textStorage.length
		? [view.textStorage attributesAtIndex:index effectiveRange:NULL] : nil;
	lua_newtable(L);
#if TARGET_OS_IPHONE
	UIFont *font = attributes[NSFontAttributeName];
	BOOL bold = (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
#else
	NSFont *font = attributes[NSFontAttributeName];
	BOOL bold = font && ([[NSFontManager sharedFontManager] traitsOfFont:font] & NSBoldFontMask) != 0;
#endif
	lua_pushboolean(L, bold); lua_setfield(L, -2, "bold");
#if TARGET_OS_IPHONE
	BOOL italic = (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0;
#else
	BOOL italic = font && ([[NSFontManager sharedFontManager] traitsOfFont:font] & NSItalicFontMask) != 0;
#endif
	lua_pushboolean(L, italic); lua_setfield(L, -2, "italic");
	lua_pushboolean(L, attributes[NSLinkAttributeName] != nil); lua_setfield(L, -2, "linked");
#if TARGET_OS_IPHONE
	UIColor *color = attributes[NSForegroundColorAttributeName];
	lua_pushboolean(L, color && CGColorGetAlpha(color.CGColor) > 0);
#else
	lua_pushboolean(L, [attributes[NSForegroundColorAttributeName] alphaComponent] > 0);
#endif
	lua_setfield(L, -2, "visible");
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
