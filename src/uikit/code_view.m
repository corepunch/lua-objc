static UIColor *code_view_color(NSString *name) {
	if ([name isEqualToString:@"systemPurple"]) return UIColor.systemPurpleColor;
	if ([name isEqualToString:@"systemRed"]) return UIColor.systemRedColor;
	if ([name isEqualToString:@"systemBlue"]) return UIColor.systemBlueColor;
	if ([name isEqualToString:@"systemTeal"]) return UIColor.systemTealColor;
	if ([name isEqualToString:@"systemOrange"]) return UIColor.systemOrangeColor;
	if ([name isEqualToString:@"systemIndigo"]) return UIColor.systemIndigoColor;
	if ([name isEqualToString:@"secondaryLabel"]) return UIColor.secondaryLabelColor;
	return UIColor.labelColor;
}

@interface LuaCodeView : UITextView
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSDictionary *syntaxRules;
- (void)highlight;
@end

@implementation LuaCodeView

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.editable = NO;
	self.selectable = YES;
	self.scrollEnabled = YES;
	self.alwaysBounceVertical = NO;
	self.backgroundColor = UIColor.secondarySystemBackgroundColor;
	self.textContainerInset = UIEdgeInsetsMake(14, 14, 14, 14);
	self.textContainer.lineFragmentPadding = 0;
	self.font = [UIFont monospacedSystemFontOfSize:kCodeFontSize weight:UIFontWeightRegular];
	self.textColor = UIColor.labelColor;
	self.directionalLockEnabled = YES;
	self.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	return self;
}

- (void)setText:(NSString *)text {
	[super setText:text ?: @""];
	[self highlight];
}

- (void)setLanguage:(NSString *)language {
	_language = [language copy] ?: @"lua";
	[self highlight];
}

- (void)setSyntaxRules:(NSDictionary *)syntaxRules {
	_syntaxRules = [syntaxRules copy] ?: @{};
	[self highlight];
}

- (void)applyMatches:(NSArray<NSDictionary *> *)matches inRange:(NSRange)limit colors:(NSDictionary *)colors {
	NSString *source = self.text ?: @"";
	if (![matches isKindOfClass:NSArray.class] || ![colors isKindOfClass:NSDictionary.class]) return;
	NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
	for (NSDictionary *rule in matches) {
		if (![rule isKindOfClass:NSDictionary.class]) continue;
		NSString *pattern = rule[@"pattern"];
		NSString *colorKey = rule[@"color"];
		if (![pattern isKindOfClass:NSString.class] || ![colorKey isKindOfClass:NSString.class]) continue;
		UIColor *color = code_view_color(colors[colorKey] ?: @"");
		if (limit.location > source.length
			|| NSMaxRange(limit) > source.length) continue;
		NSError *error = nil;
		NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern
			options:0 error:&error];
		if (!expression || error) continue;
		[expression enumerateMatchesInString:source options:0 range:limit
			usingBlock:^(NSTextCheckingResult *match, __unused NSMatchingFlags flags, __unused BOOL *stop) {
				if (match.range.location != NSNotFound && match.range.length > 0) {
					[candidates addObject:@{ @"location": @(match.range.location), @"length": @(match.range.length), @"color": color }];
				}
			}];
	}
	[candidates sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		NSUInteger leftLocation = [left[@"location"] unsignedIntegerValue];
		NSUInteger rightLocation = [right[@"location"] unsignedIntegerValue];
		if (leftLocation < rightLocation) return NSOrderedAscending;
		if (leftLocation > rightLocation) return NSOrderedDescending;
		NSUInteger leftLength = [left[@"length"] unsignedIntegerValue];
		NSUInteger rightLength = [right[@"length"] unsignedIntegerValue];
		if (leftLength > rightLength) return NSOrderedAscending;
		if (leftLength < rightLength) return NSOrderedDescending;
		return NSOrderedSame;
	}];
	NSUInteger coveredThrough = limit.location;
	for (NSDictionary *candidate in candidates) {
		NSUInteger location = [candidate[@"location"] unsignedIntegerValue];
		NSUInteger length = [candidate[@"length"] unsignedIntegerValue];
		if (location < coveredThrough || NSMaxRange(limit) < location + length) continue;
		[self.textStorage addAttribute:NSForegroundColorAttributeName value:candidate[@"color"]
			range:NSMakeRange(location, length)];
		coveredThrough = location + length;
	}
}

- (void)applyRegions:(NSArray<NSDictionary *> *)regions inRange:(NSRange)limit colors:(NSDictionary *)colors {
	NSString *source = self.text ?: @"";
	if (![regions isKindOfClass:NSArray.class] || ![colors isKindOfClass:NSDictionary.class]) return;
	for (NSDictionary *region in regions) {
		if (![region isKindOfClass:NSDictionary.class]) continue;
		NSString *startPattern = region[@"start"];
		NSString *stopPattern = region[@"stop"];
		if (![startPattern isKindOfClass:NSString.class] || ![stopPattern isKindOfClass:NSString.class]) continue;
		NSError *error = nil;
		NSRegularExpression *startExpression = [NSRegularExpression regularExpressionWithPattern:startPattern
			options:0 error:&error];
		NSRegularExpression *stopExpression = [NSRegularExpression regularExpressionWithPattern:stopPattern
			options:0 error:&error];
		if (!startExpression || !stopExpression || error) continue;
		NSUInteger cursor = limit.location;
		while (cursor < NSMaxRange(limit)) {
			NSTextCheckingResult *opening = [startExpression firstMatchInString:source options:0
				range:NSMakeRange(cursor, NSMaxRange(limit) - cursor)];
			if (!opening) break;
			NSUInteger bodyStart = NSMaxRange(opening.range);
			NSTextCheckingResult *closing = [stopExpression firstMatchInString:source options:0
				range:NSMakeRange(bodyStart, NSMaxRange(limit) - bodyStart)];
			NSUInteger bodyEnd = closing ? closing.range.location : NSMaxRange(limit);
			NSString *delimiter = region[@"delimiter"];
			if ([delimiter isKindOfClass:NSString.class]) {
				UIColor *color = code_view_color(colors[delimiter] ?: @"");
				[self.textStorage addAttribute:NSForegroundColorAttributeName value:color range:opening.range];
				if (closing) [self.textStorage addAttribute:NSForegroundColorAttributeName value:color range:closing.range];
			}
		id nestedValue = region[@"rules"];
		NSDictionary *nested = [nestedValue isKindOfClass:NSDictionary.class] ? nestedValue : nil;
		[self applyMatches:nested[@"matches"] inRange:NSMakeRange(bodyStart, bodyEnd - bodyStart) colors:colors];
		[self applyRegions:nested[@"regions"] inRange:NSMakeRange(bodyStart, bodyEnd - bodyStart) colors:colors];
			cursor = closing ? NSMaxRange(closing.range) : NSMaxRange(limit);
		}
	}
}

- (void)highlight {
	NSString *source = self.text ?: @"";
	if (source.length == 0) return;
	id root = [self.syntaxRules isKindOfClass:NSDictionary.class] ? self.syntaxRules : nil;
	id colorValue = [root isKindOfClass:NSDictionary.class] ? root[@"colors"] : nil;
	id languageMap = [root isKindOfClass:NSDictionary.class] ? root[@"languages"] : nil;
	NSDictionary *colors = [colorValue isKindOfClass:NSDictionary.class] ? colorValue : @{};
	id languageValue = [languageMap isKindOfClass:NSDictionary.class]
		? languageMap[self.language ?: @"lua"] : nil;
	NSDictionary *languageRules = [languageValue isKindOfClass:NSDictionary.class] ? languageValue : nil;
	UIFont *font = [UIFont monospacedSystemFontOfSize:kCodeFontSize weight:UIFontWeightRegular];
	NSDictionary *base = @{
		NSFontAttributeName: font,
		NSForegroundColorAttributeName: UIColor.labelColor,
	};
	[self.textStorage beginEditing];
	[self.textStorage setAttributes:base range:NSMakeRange(0, source.length)];
	[self applyMatches:languageRules[@"matches"] inRange:NSMakeRange(0, source.length) colors:colors];
	[self applyRegions:languageRules[@"regions"] inRange:NSMakeRange(0, source.length) colors:colors];
	[self.textStorage endEditing];
}

@end

static int bridge_UIKitControls_codeView(lua_State *L) {
	LuaCodeView *view = [[LuaCodeView alloc] initWithFrame:CGRectZero];
	view.syntaxRules = lua_isnoneornil(L, 3) ? @{} : lua_to_objc_value(L, 3);
	const char *language = luaL_optstring(L, 2, "lua");
	view.language = [NSString stringWithUTF8String:language];
	const char *text = luaL_optstring(L, 1, "");
	view.text = [NSString stringWithUTF8String:text];
	push_objc(L, view, "uiview");
	return 1;
}
