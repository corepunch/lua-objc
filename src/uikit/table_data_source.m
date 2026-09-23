#pragma mark - LuaTableViewSource (iOS UITableView)

@interface LuaTableViewSource : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) UITableView *tableView;
@property (nonatomic, strong) LuaReg *moveReg;
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

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return lua_reg_live_state(_moveReg) != NULL;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
		 toIndexPath:(NSIndexPath *)destinationIndexPath {
	NSInteger from = sourceIndexPath.row;
	NSInteger to = destinationIndexPath.row;
	if (from < 0 || from >= (NSInteger)_rows.count || to < 0 || to >= (NSInteger)_rows.count || from == to) return;
	id moved = _rows[(NSUInteger)from];
	[_rows removeObjectAtIndex:(NSUInteger)from];
	[_rows insertObject:moved atIndex:(NSUInteger)to];
	lua_State *callL = lua_reg_live_state(_moveReg);
	if (!callL || !lua_reg_push(_moveReg)) return;
	push_objc(callL, tableView, "uiview");
	lua_pushinteger(callL, (lua_Integer)from + 1);
	lua_pushinteger(callL, (lua_Integer)to + 1);
	lua_objc_pcall(callL, 3, 0, "table row move");
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
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
