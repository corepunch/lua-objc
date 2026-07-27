#pragma mark - LuaTableViewSource (iOS UITableView)

@interface LuaTableViewSource : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) UITableView *tableView;
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

