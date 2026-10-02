#pragma mark - Value formatters

/* The schema type tags <Bytes>, <Number>, <Percent> and <Date> (lua/data/
 * schema.lua) convert on the system formatters, so a size reads as Finder
 * writes it and a date follows the person's locale. Both platforms share
 * Foundation's formatters. Lua passes plain numbers; every function returns
 * a string. */

// _formatBytes(count) -> "1.2 GB" (decimal units, as Finder shows sizes)
static int bridge_format_bytes(lua_State *L) {
	NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
	formatter.countStyle = NSByteCountFormatterCountStyleFile;
	lua_pushstring(L, [formatter stringFromByteCount:(long long)luaL_checknumber(L, 1)].UTF8String);
	return 1;
}

// _formatNumber(value, digits) -> "1,234.5" with the locale's separators
static int bridge_format_number(lua_State *L) {
	NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
	formatter.numberStyle = NSNumberFormatterDecimalStyle;
	NSInteger digits = (NSInteger)luaL_optinteger(L, 2, 0);
	formatter.minimumFractionDigits = digits;
	formatter.maximumFractionDigits = digits;
	lua_pushstring(L, [formatter stringFromNumber:@(luaL_checknumber(L, 1))].UTF8String);
	return 1;
}

// _formatPercent(fraction, digits) -> "34%" for 0.34
static int bridge_format_percent(lua_State *L) {
	NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
	formatter.numberStyle = NSNumberFormatterPercentStyle;
	NSInteger digits = (NSInteger)luaL_optinteger(L, 2, 0);
	formatter.minimumFractionDigits = digits;
	formatter.maximumFractionDigits = digits;
	lua_pushstring(L, [formatter stringFromNumber:@(luaL_checknumber(L, 1))].UTF8String);
	return 1;
}

// _formatDate(seconds, style [, now]) -> style "relative" reads "2 days ago"
// relative to `now` (default: the current time); "short", "medium" and
// "long" are the locale's date styles.
static int bridge_format_date(lua_State *L) {
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:luaL_checknumber(L, 1)];
	NSString *style = [NSString stringWithUTF8String:luaL_optstring(L, 2, "medium")];
	if ([style isEqualToString:@"relative"]) {
		NSRelativeDateTimeFormatter *formatter = [[NSRelativeDateTimeFormatter alloc] init];
		formatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;
		NSDate *now = lua_isnumber(L, 3)
			? [NSDate dateWithTimeIntervalSince1970:lua_tonumber(L, 3)] : [NSDate date];
		lua_pushstring(L, [formatter localizedStringForDate:date relativeToDate:now].UTF8String);
		return 1;
	}
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = [style isEqualToString:@"short"] ? NSDateFormatterShortStyle
		: [style isEqualToString:@"long"] ? NSDateFormatterLongStyle : NSDateFormatterMediumStyle;
	formatter.timeStyle = NSDateFormatterNoStyle;
	lua_pushstring(L, [formatter stringFromDate:date].UTF8String);
	return 1;
}

#define LUA_OBJC_FORMATTER_FUNCTIONS \
	{"_formatBytes", bridge_format_bytes}, \
	{"_formatNumber", bridge_format_number}, \
	{"_formatPercent", bridge_format_percent}, \
	{"_formatDate", bridge_format_date},
