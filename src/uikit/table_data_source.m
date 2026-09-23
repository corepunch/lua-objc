#pragma mark - LuaTableViewSource (iOS UITableView)

@interface LuaTableViewSource : NSObject <UITableViewDataSource, UITableViewDelegate,
	UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) UITableView *tableView;
@property (nonatomic, strong) LuaReg *moveReg;
@property (nonatomic, strong) LuaReg *leadingSwipeReg;
@property (nonatomic, strong) LuaReg *trailingSwipeReg;
@property (nonatomic, copy) NSString *leadingSwipeTitle;
@property (nonatomic, copy) NSString *trailingSwipeTitle;
@property (nonatomic) BOOL leadingSwipeDestructive;
@property (nonatomic) BOOL trailingSwipeDestructive;
@property (nonatomic) BOOL leadingFullSwipe;
@property (nonatomic) BOOL trailingFullSwipe;
- (BOOL)invokeSwipeAtRow:(NSInteger)row leading:(BOOL)leading;
- (void)moveRowFrom:(NSInteger)from to:(NSInteger)to;
@end

@implementation LuaTableViewSource

- (instancetype)initWithTableView:(UITableView *)tv columns:(NSArray *)cols {
	self = [super init];
	if (self) {
		_tableView = tv;
		_columns = [cols mutableCopy];
		_rows = [NSMutableArray array];
		tv.dataSource = self;
		tv.delegate = self;
		[tv registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
	}
	return self;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)_rows.count;
}

- (BOOL)invokeSwipeAtRow:(NSInteger)row leading:(BOOL)leading {
	if (row < 0 || row >= (NSInteger)_rows.count) return NO;
	LuaReg *reg = leading ? self.leadingSwipeReg : self.trailingSwipeReg;
	lua_State *callL = lua_reg_live_state(reg);
	if (!callL || !lua_reg_push(reg)) return NO;
	push_objc(callL, self.tableView, "uiview");
	lua_pushinteger(callL, (lua_Integer)row + 1);
	lua_newtable(callL);
	NSDictionary *rowData = self.rows[(NSUInteger)row];
	for (NSString *key in rowData) {
		push_objc_value(callL, rowData[key]);
		lua_setfield(callL, -2, key.UTF8String);
	}
	return lua_objc_pcall(callL, 3, 0, "table row swipe") == LUA_OK;
}

- (UISwipeActionsConfiguration *)swipeConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
		leading:(BOOL)leading {
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)_rows.count) return nil;
	LuaReg *reg = leading ? self.leadingSwipeReg : self.trailingSwipeReg;
	if (!lua_reg_live_state(reg)) return nil;
	NSString *title = leading ? self.leadingSwipeTitle : self.trailingSwipeTitle;
	BOOL destructive = leading ? self.leadingSwipeDestructive : self.trailingSwipeDestructive;
	BOOL fullSwipe = leading ? self.leadingFullSwipe : self.trailingFullSwipe;
	UIContextualAction *action = [UIContextualAction contextualActionWithStyle:
		(destructive ? UIContextualActionStyleDestructive : UIContextualActionStyleNormal)
		title:title ?: @"Action" handler:^(UIContextualAction *selected, UIView *sourceView,
		void (^completion)(BOOL)) {
		(void)selected; (void)sourceView;
		completion([self invokeSwipeAtRow:indexPath.row leading:leading]);
	}];
	UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[action]];
	configuration.performsFirstActionWithFullSwipe = fullSwipe;
	return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
		leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView;
	return [self swipeConfigurationForRowAtIndexPath:indexPath leading:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
		trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView;
	return [self swipeConfigurationForRowAtIndexPath:indexPath leading:NO];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return lua_reg_live_state(_moveReg) != NULL;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
		 toIndexPath:(NSIndexPath *)destinationIndexPath {
	(void)tableView;
	[self moveRowFrom:sourceIndexPath.row to:destinationIndexPath.row];
}

- (void)moveRowFrom:(NSInteger)from to:(NSInteger)to {
	if (from < 0 || from >= (NSInteger)_rows.count || to < 0 || to >= (NSInteger)_rows.count || from == to) return;
	id moved = _rows[(NSUInteger)from];
	[_rows removeObjectAtIndex:(NSUInteger)from];
	[_rows insertObject:moved atIndex:(NSUInteger)to];
	lua_State *callL = lua_reg_live_state(_moveReg);
	if (!callL || !lua_reg_push(_moveReg)) return;
	push_objc(callL, self.tableView, "uiview");
	lua_pushinteger(callL, (lua_Integer)from + 1);
	lua_pushinteger(callL, (lua_Integer)to + 1);
	lua_objc_pcall(callL, 3, 0, "table row move");
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView
		itemsForBeginningDragSession:(id<UIDragSession>)session
		atIndexPath:(NSIndexPath *)indexPath {
	(void)tableView; (void)session;
	if (!lua_reg_live_state(_moveReg) || indexPath.row >= (NSInteger)_rows.count) return @[];
	NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:
		[NSString stringWithFormat:@"lua-objc-row-%ld", (long)indexPath.row]];
	UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
	item.localObject = self;
	return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView
		dropSessionDidUpdate:(id<UIDropSession>)session
		withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
	(void)tableView; (void)destinationIndexPath;
	if (!lua_reg_live_state(_moveReg) || !session.localDragSession ||
		session.items.count != 1 || session.items.firstObject.localObject != self)
		return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
	return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
		intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView
		performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
	id<UITableViewDropItem> item = coordinator.items.firstObject;
	NSIndexPath *source = item.sourceIndexPath;
	if (!source || item.dragItem.localObject != self || _rows.count == 0) return;
	NSInteger to = coordinator.destinationIndexPath
		? coordinator.destinationIndexPath.row : (NSInteger)_rows.count - 1;
	to = MIN(MAX(to, 0), (NSInteger)_rows.count - 1);
	if (source.row == to) return;
	NSIndexPath *destination = [NSIndexPath indexPathForRow:to inSection:0];
	[tableView performBatchUpdates:^{
		[tableView moveRowAtIndexPath:source toIndexPath:destination];
	} completion:nil];
	[self moveRowFrom:source.row to:to];
	[coordinator dropItem:item.dragItem toRowAtIndexPath:destination];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	LUA_OBJC_PERF_BEGIN("uikit.cell.dequeue", signpost);
	NSDictionary *rowData = _rows[indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"
														   forIndexPath:indexPath];

	NSArray *keys = [_columns valueForKey:@"id"];
	NSMutableArray *values = [NSMutableArray array];
	for (NSString *key in keys) {
		id val = rowData[key];
		[values addObject:val ? [val description] : @""];
	}
	cell.textLabel.text = [values componentsJoinedByString:@"  "];
	LUA_OBJC_PERF_END("uikit.cell.dequeue", signpost);
	return cell;
}

- (void)addRow:(NSDictionary *)row {
	[_rows addObject:row];
	NSIndexPath *ip = [NSIndexPath indexPathForRow:(NSInteger)_rows.count - 1 inSection:0];
	[_tableView insertRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)removeRowAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_rows.count) return;
	[_rows removeObjectAtIndex:(NSUInteger)index];
	NSIndexPath *ip = [NSIndexPath indexPathForRow:index inSection:0];
	[_tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)clearRows {
	[_rows removeAllObjects];
	[_tableView reloadData];
}

@end
