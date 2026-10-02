#pragma mark - Column content templates

/* SwiftUI `TableColumn { row in ... }`, WPF's DataTemplate: a column's child
 * XML is built once per reusable cell, by the framework's own constructors,
 * and laid out by the framework's own layout engine. Attributes written
 * `$field` are row bindings. Lua builds a cell's views and lists its
 * bindings when AppKit has no cell to reuse; after that the bindings are
 * applied here, through KVC, each time the cell is given a row. Scrolling
 * never enters Lua. */

typedef NS_ENUM(NSInteger, LuaCellBindingKind) {
	LuaCellBindingString,
	LuaCellBindingNumber,
	LuaCellBindingBool,
	LuaCellBindingColor,
};

@interface LuaCellBinding : NSObject
@property(nonatomic, strong) NSView *view;
@property(nonatomic, copy) NSString *key;
@property(nonatomic) LuaCellBindingKind kind;
// The row field path, one key per level: `$size.color` is @[@"size", @"color"].
@property(nonatomic, copy) NSArray<NSString *> *path;
@property(nonatomic) BOOL negate;
// What the view was built with; a row without the field returns to it.
@property(nonatomic, strong) id fallback;
@end
@implementation LuaCellBinding
@end

/* A field counts as present unless it is missing, false or an empty string.
 * Zero is a value: a measured share of 0 is still measured. */
static BOOL cell_binding_truthy(id value) {
	if (!value || value == NSNull.null) return NO;
	if ([value isKindOfClass:NSString.class]) return [value length] > 0;
	if ((__bridge CFTypeRef)value == kCFBooleanFalse) return NO;
	return YES;
}

/* A path reaches into nested fields; a level that is not a dictionary ends
 * it with nothing, as a missing field. */
static id cell_binding_field(NSDictionary *row, NSArray<NSString *> *path) {
	id value = row;
	for (NSString *key in path) {
		if (![value isKindOfClass:NSDictionary.class]) return nil;
		value = value[key];
	}
	return value == NSNull.null ? nil : value;
}

static id cell_binding_value(LuaCellBinding *binding, NSDictionary *row) {
	id value = cell_binding_field(row, binding.path);
	if (binding.kind == LuaCellBindingBool)
		return @(cell_binding_truthy(value) != binding.negate);
	if (!value) return binding.fallback;
	switch (binding.kind) {
	case LuaCellBindingNumber: {
		if (![value respondsToSelector:@selector(doubleValue)]) return binding.fallback;
		double number = [value doubleValue];
		return isfinite(number) ? @(number) : binding.fallback;
	}
	case LuaCellBindingColor:
		return semantic_color([value description]);
	default:
		return [value description];
	}
}

@interface LuaTemplateCellView : NSTableCellView
@property(nonatomic, strong) NSView *content;
@property(nonatomic, copy) NSArray<LuaCellBinding *> *bindings;
- (void)bindRow:(NSDictionary *)row;
@end

static void template_cell_set_background_style(NSView *view, NSBackgroundStyle style) {
	for (NSView *child in view.subviews) {
		if ([child isKindOfClass:NSControl.class]) {
			NSCell *cell = ((NSControl *)child).cell;
			if (cell) cell.backgroundStyle = style;
		}
		template_cell_set_background_style(child, style);
	}
}

static NSView *template_cell_first(NSView *view, Class class) {
	if ([view isKindOfClass:class]) return view;
	for (NSView *child in view.subviews) {
		NSView *found = template_cell_first(child, class);
		if (found) return found;
	}
	return nil;
}

@implementation LuaTemplateCellView

- (void)setContent:(NSView *)content {
	[_content removeFromSuperview];
	_content = content;
	if (!content) return;
	[self addSubview:content];
	/* The outlets AppKit reads for the cell's accessibility and for its
	 * selected-row text colour. */
	self.textField = (NSTextField *)template_cell_first(content, NSTextField.class);
	self.imageView = (NSImageView *)template_cell_first(content, NSImageView.class);
}

/* NSTableCellView tells only its own subviews about the row's selection;
 * a template's labels sit deeper, inside stacks. */
- (void)setBackgroundStyle:(NSBackgroundStyle)style {
	[super setBackgroundStyle:style];
	template_cell_set_background_style(self, style);
}

- (void)bindRow:(NSDictionary *)row {
	for (LuaCellBinding *binding in _bindings) {
		id value = cell_binding_value(binding, row);
		@try {
			[binding.view setValue:value forKey:binding.key];
		} @catch (NSException *exception) {
			NSLog(@"lua-objc: cell template cannot bind '%@' on %@: %@",
				binding.key, NSStringFromClass(binding.view.class), exception.reason);
		}
	}
	[self setNeedsLayout:YES];
}

/* The content takes the column's width inside the text cells' insets, so
 * template and text columns align, and its own height, centred in the row
 * as SwiftUI centres a table cell. */
- (void)layout {
	[super layout];
	if (!_content) return;
	NSSize bounds = self.bounds.size;
	CGFloat width = MAX(0, bounds.width - kTableCellTextLeadingInset - kTableCellTextTrailingInset);
	NSSize size = measure_view(_content, (LuaLayoutConstraint){
		.width = width, .height = 0,
		.widthMode = LuaMeasureExactly, .heightMode = LuaMeasureUndefined });
	CGFloat height = MIN(ceil(size.height), bounds.height);
	_content.frame = NSMakeRect(kTableCellTextLeadingInset,
		floor((bounds.height - height) / 2), width, height);
	layout_recursive(_content, width);
}

@end

static LuaCellBinding *template_cell_binding(lua_State *L, int idx) {
	static NSDictionary<NSString *, NSNumber *> *kinds;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		kinds = @{ @"string": @(LuaCellBindingString), @"number": @(LuaCellBindingNumber),
			@"bool": @(LuaCellBindingBool), @"color": @(LuaCellBindingColor) };
	});
	idx = lua_absindex(L, idx);
	LuaCellBinding *binding = [[LuaCellBinding alloc] init];
	lua_getfield(L, idx, "view");
	binding.view = check_view(L, -1);
	lua_getfield(L, idx, "key");
	binding.key = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
	lua_getfield(L, idx, "kind");
	NSNumber *kind = kinds[[NSString stringWithUTF8String:luaL_checkstring(L, -1)]];
	if (!kind) luaL_error(L, "unknown cell binding kind");
	binding.kind = kind.integerValue;
	lua_getfield(L, idx, "negate");
	binding.negate = lua_toboolean(L, -1);
	lua_getfield(L, idx, "path");
	binding.path = lua_to_objc_value(L, -1);
	lua_pop(L, 5);
	@try {
		binding.fallback = [binding.view valueForKey:binding.key];
	} @catch (NSException *exception) {
		luaL_error(L, "cell template: %s has no property '%s'",
			NSStringFromClass(binding.view.class).UTF8String, binding.key.UTF8String);
	}
	return binding;
}

/* Runs the column's Lua factory: it returns the template's root view and
 * the list of its row bindings. */
static BOOL template_cell_build(LuaTemplateCellView *cell, LuaReg *factory) {
	lua_State *L = lua_reg_live_state(factory);
	if (!L || !lua_reg_push(factory)) return NO;
	if (lua_objc_pcall(L, 0, 2, "table cell template") != LUA_OK) return NO;
	int top = lua_gettop(L);
	if (!lua_isuserdata(L, top - 1) || !lua_istable(L, top)) {
		lua_pop(L, 2);
		return NO;
	}
	cell.content = check_view(L, top - 1);
	NSMutableArray *bindings = [NSMutableArray array];
	lua_Integer count = luaL_len(L, top);
	for (lua_Integer i = 1; i <= count; i++) {
		lua_rawgeti(L, top, i);
		[bindings addObject:template_cell_binding(L, -1)];
		lua_pop(L, 1);
	}
	cell.bindings = bindings;
	lua_pop(L, 2);
	return YES;
}

static NSView *table_template_cell_view(NSTableView *tableView, NSTableColumn *column,
		NSDictionary *rowData, id owner) {
	LuaReg *factory = objc_getAssociatedObject(column, &kKeys[kColumnTemplateKey]);
	NSString *reuseId = [@"template-" stringByAppendingString:column.identifier];
	LuaTemplateCellView *cell = (LuaTemplateCellView *)[tableView
		makeViewWithIdentifier:reuseId owner:owner];
	if (!cell) {
		cell = [[LuaTemplateCellView alloc] initWithFrame:
			NSMakeRect(0, 0, column.width, tableView.rowHeight)];
		cell.identifier = reuseId;
		if (!template_cell_build(cell, factory)) return cell;
		NSNumber *built = objc_getAssociatedObject(tableView, &kKeys[kTableTemplateCellsKey]);
		objc_setAssociatedObject(tableView, &kKeys[kTableTemplateCellsKey],
			@(built.integerValue + 1), OBJC_ASSOCIATION_RETAIN);
	}
	[cell bindRow:rowData];
	return cell;
}

// _tableColumnTemplate(list, columnId, factory)
static int bridge_table_column_template(lua_State *L) {
	NSScrollView *scroll = check_objc(L, 1);
	NSTableView *table = (NSTableView *)scroll.documentView;
	if (![table isKindOfClass:NSTableView.class]) return luaL_error(L, "not a table view");
	NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	NSTableColumn *column = [table tableColumnWithIdentifier:identifier];
	if (!column) return luaL_error(L, "no column '%s'", identifier.UTF8String);
	lua_reg_store(column, &kKeys[kColumnTemplateKey], lua_reg_create(L, 3, YES));
	return 0;
}

// _tableTemplateCells(list): how many cells the templates have built.
static int bridge_table_template_cells(lua_State *L) {
	NSScrollView *scroll = check_objc(L, 1);
	NSNumber *built = objc_getAssociatedObject(scroll.documentView, &kKeys[kTableTemplateCellsKey]);
	lua_pushinteger(L, built.integerValue);
	return 1;
}
