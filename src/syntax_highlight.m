#pragma mark - Syntax highlighting (NSTextStorage subclass)

/* Per-language rule table. */
typedef struct {
	const char * const *keywords;
	NSUInteger         keywordCount;
	const char * const *types;
	NSUInteger         typeCount;
	BOOL               hasPreprocessor;  /* C-family # directives */
	BOOL               luaStyle;         /* --  single-line comment, [[ block ]] */
} SyntaxRules;

/* ── keyword/type tables ─────────────────────────────────────────────────── */

static const char * const kKW_C[] = {
	"auto","break","case","continue","default","do","else","enum","extern",
	"for","goto","if","inline","register","return","sizeof","static",
	"struct","switch","typedef","union","volatile","while",
	"NULL","true","false","nullptr",
};
static const char * const kTY_C[] = {
	"char","double","float","int","long","short","signed","unsigned","void",
	"bool","int8_t","int16_t","int32_t","int64_t",
	"uint8_t","uint16_t","uint32_t","uint64_t","size_t","ptrdiff_t",
	"intptr_t","uintptr_t","wchar_t",
};

static const char * const kKW_CPP[] = {
	"auto","break","case","catch","class","const","const_cast","continue",
	"default","delete","do","dynamic_cast","else","enum","explicit","export",
	"extern","for","friend","goto","if","inline","mutable","namespace","new",
	"operator","private","protected","public","register","reinterpret_cast",
	"return","sizeof","static","static_cast","struct","switch","template",
	"this","throw","try","typedef","typeid","typename","union","using",
	"virtual","volatile","while",
	"nullptr","true","false","override","final","noexcept","constexpr",
	"decltype","static_assert","thread_local","alignas","alignof",
};
static const char * const kTY_CPP[] = {
	"bool","char","double","float","int","long","short","signed","unsigned",
	"void","wchar_t","char8_t","char16_t","char32_t","auto",
	"int8_t","int16_t","int32_t","int64_t",
	"uint8_t","uint16_t","uint32_t","uint64_t","size_t","ptrdiff_t",
	"string","vector","map","set","unordered_map","unordered_set",
	"pair","tuple","optional","variant","shared_ptr","unique_ptr","weak_ptr",
};

static const char * const kKW_OBJC[] = {
	"auto","break","case","continue","default","do","else","enum","extern",
	"for","goto","if","inline","register","return","sizeof","static",
	"struct","switch","typedef","union","volatile","while",
	"@interface","@implementation","@end","@property","@synthesize",
	"@dynamic","@protocol","@optional","@required","@class","@selector",
	"@encode","@try","@catch","@finally","@throw","@synchronized",
	"@autoreleasepool","@import",
	"nil","Nil","YES","NO","NULL","true","false","self","super","_cmd",
	"IBOutlet","IBAction","IBInspectable","NS_ENUM","NS_OPTIONS",
	"NS_ASSUME_NONNULL_BEGIN","NS_ASSUME_NONNULL_END",
	"nullable","nonnull","__weak","__strong","__unsafe_unretained","__block",
	"nonatomic","atomic","readonly","readwrite","assign","retain","copy",
	"strong","weak","unsafe_unretained",
};
static const char * const kTY_OBJC[] = {
	"char","double","float","int","long","short","signed","unsigned","void",
	"bool","BOOL","id","SEL","Class","IMP","NSInteger","NSUInteger",
	"CGFloat","CGPoint","CGSize","CGRect","NSRange","NSString","NSArray",
	"NSDictionary","NSSet","NSNumber","NSData","NSDate","NSURL",
	"NSError","NSObject","NSView","NSWindow","NSButton","NSTextField",
	"instancetype","Protocol",
};

static const char * const kKW_SWIFT[] = {
	"as","break","case","catch","class","continue","default","defer","deinit",
	"do","else","enum","extension","fallthrough","false","fileprivate","for",
	"func","guard","if","import","in","init","inout","internal","is","lazy",
	"let","nil","open","operator","override","precondition","preconditionFailure",
	"prefix","private","protocol","public","repeat","required","rethrows",
	"return","self","Self","static","struct","subscript","super","switch",
	"throw","throws","true","try","typealias","var","where","while",
	"associatedtype","convenience","didSet","dynamic","final","get","indirect",
	"infix","mutating","nonmutating","optional","postfix","precedencegroup",
	"set","some","Type","unowned","weak","willSet","async","await","actor",
	"nonisolated","distributed","@main","@discardableResult","@objc",
	"@IBOutlet","@IBAction","@Published","@State","@Binding","@Environment",
	"@EnvironmentObject","@StateObject","@ObservedObject","@ViewBuilder",
};
static const char * const kTY_SWIFT[] = {
	"Bool","Int","Int8","Int16","Int32","Int64","UInt","UInt8","UInt16",
	"UInt32","UInt64","Float","Double","String","Character","Array",
	"Dictionary","Set","Optional","Result","Never","Void","Any","AnyObject",
	"CGFloat","CGPoint","CGSize","CGRect",
};

static const char * const kKW_LUA[] = {
	"and","break","do","else","elseif","end","false","for","function",
	"goto","if","in","local","nil","not","or","repeat","return","then",
	"true","until","while",
};
static const char * const kTY_LUA[] = {
	/* Lua standard library globals */
	"print","type","tostring","tonumber","pairs","ipairs","next","select",
	"unpack","table","string","math","io","os","coroutine","package",
	"require","pcall","xpcall","error","assert","rawget","rawset","rawlen",
	"rawequal","setmetatable","getmetatable","load","loadfile","dofile",
	"collectgarbage","gcinfo",
};

/* ── color helpers ──────────────────────────────────────────────────────── */

/* Returns a color that adapts automatically to light/dark appearance. */
static NSColor *syntax_color(CGFloat lr, CGFloat lg, CGFloat lb,
                              CGFloat dr, CGFloat dg, CGFloat db) {
	return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) {
		NSAppearanceName best = [a bestMatchFromAppearancesWithNames:@[
			NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
		if ([best isEqualToString:NSAppearanceNameDarkAqua])
			return [NSColor colorWithSRGBRed:dr green:dg blue:db alpha:1];
		return [NSColor colorWithSRGBRed:lr green:lg blue:lb alpha:1];
	}];
}

/* Color theme — maps token categories to dynamic light/dark colors.
   Struct-based so a future bridge API can swap themes per text view.   */
typedef struct {
	NSColor *comment;
	NSColor *string;
	NSColor *number;
	NSColor *keyword;
	NSColor *type;
	NSColor *preprocessor;
	NSColor *operator;
	NSColor *property;        /* .field or :method (no parens)          */
	NSColor *functionCall;    /* .method() or :method()                 */
	NSColor *defaultColor;
} SyntaxTheme;

static SyntaxTheme g_theme;

static void theme_init_default(void) {
	if (g_theme.defaultColor) return;
	g_theme.comment      = syntax_color(0.40f,0.47f,0.40f,  0.44f,0.54f,0.44f);
	g_theme.string       = syntax_color(0.75f,0.12f,0.10f,  0.98f,0.40f,0.36f);
	g_theme.number       = syntax_color(0.10f,0.40f,0.75f,  0.36f,0.72f,1.00f);
	g_theme.keyword      = syntax_color(0.62f,0.00f,0.57f,  0.92f,0.38f,0.90f);
	g_theme.type         = syntax_color(0.10f,0.46f,0.65f,  0.29f,0.72f,0.88f);
	g_theme.preprocessor = syntax_color(0.50f,0.35f,0.00f,  0.80f,0.62f,0.18f);
	g_theme.operator     = syntax_color(0.30f,0.30f,0.30f,  0.65f,0.65f,0.65f);
	g_theme.property     = syntax_color(0.70f,0.35f,0.00f,  0.90f,0.60f,0.22f);
	g_theme.functionCall = syntax_color(0.33f,0.24f,0.65f,  0.60f,0.55f,0.88f);
	g_theme.defaultColor = [NSColor labelColor];
}

/* ── SyntaxRules factory ─────────────────────────────────────────────────── */

static SyntaxRules syntax_rules_for_language(NSString *lang) {
	SyntaxRules r = {0};
	if ([lang isEqualToString:@"c"]) {
		r.keywords = kKW_C;  r.keywordCount = sizeof(kKW_C)/sizeof(*kKW_C);
		r.types    = kTY_C;  r.typeCount    = sizeof(kTY_C)/sizeof(*kTY_C);
		r.hasPreprocessor = YES;
	} else if ([lang isEqualToString:@"cpp"] || [lang isEqualToString:@"c++"]) {
		r.keywords = kKW_CPP; r.keywordCount = sizeof(kKW_CPP)/sizeof(*kKW_CPP);
		r.types    = kTY_CPP; r.typeCount    = sizeof(kTY_CPP)/sizeof(*kTY_CPP);
		r.hasPreprocessor = YES;
	} else if ([lang isEqualToString:@"objc"] || [lang isEqualToString:@"objective-c"]) {
		r.keywords = kKW_OBJC; r.keywordCount = sizeof(kKW_OBJC)/sizeof(*kKW_OBJC);
		r.types    = kTY_OBJC; r.typeCount    = sizeof(kTY_OBJC)/sizeof(*kTY_OBJC);
		r.hasPreprocessor = YES;
	} else if ([lang isEqualToString:@"swift"]) {
		r.keywords = kKW_SWIFT; r.keywordCount = sizeof(kKW_SWIFT)/sizeof(*kKW_SWIFT);
		r.types    = kTY_SWIFT; r.typeCount    = sizeof(kTY_SWIFT)/sizeof(*kTY_SWIFT);
	} else if ([lang isEqualToString:@"lua"]) {
		r.keywords = kKW_LUA; r.keywordCount = sizeof(kKW_LUA)/sizeof(*kKW_LUA);
		r.types    = kTY_LUA; r.typeCount    = sizeof(kTY_LUA)/sizeof(*kTY_LUA);
		r.luaStyle = YES;
	}
	return r;
}

/* ── SyntaxTextStorage ───────────────────────────────────────────────────── */

@interface SyntaxTextStorage : NSTextStorage {
	NSMutableAttributedString *_backing;
	SyntaxRules _rules;
	NSString    *_language;
	NSFont      *_font;
	NSDictionary *_baseAttrs;
}
@property (nonatomic, copy) NSString *language;
- (void)setEditorFont:(NSFont *)font;
@end

@implementation SyntaxTextStorage

- (instancetype)init {
	if (!(self = [super init])) return nil;
	_backing = [[NSMutableAttributedString alloc] init];
	theme_init_default();
	_font = [NSFont monospacedSystemFontOfSize:kEditorFontSize weight:NSFontWeightRegular];
	_baseAttrs = @{
		NSFontAttributeName: _font,
		NSForegroundColorAttributeName: [NSColor labelColor],
	};
	return self;
}

/* NSTextStorage primitive overrides */
- (NSString *)string { return _backing.string; }

- (NSDictionary<NSAttributedStringKey,id> *)attributesAtIndex:(NSUInteger)i
                                              effectiveRange:(NSRangePointer)r {
	return [_backing attributesAtIndex:i effectiveRange:r];
}

- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s {
	NSUInteger delta = s.length - r.length;
	[_backing replaceCharactersInRange:r withString:s];
	[self edited:NSTextStorageEditedCharacters range:r changeInLength:delta];
}

- (void)setAttributes:(NSDictionary<NSAttributedStringKey,id> *)a range:(NSRange)r {
	[_backing setAttributes:a range:r];
	[self edited:NSTextStorageEditedAttributes range:r changeInLength:0];
}

- (void)setEditorFont:(NSFont *)font {
	_font = font;
	_baseAttrs = @{
		NSFontAttributeName: _font,
		NSForegroundColorAttributeName: [NSColor labelColor],
	};
}

- (void)setLanguage:(NSString *)lang {
	_language = [lang copy];
	_rules = syntax_rules_for_language(lang);
	[self highlight];
}

/* ── Full re-highlight ──────────────────────────────────────────────────── */
- (void)highlight {
	NSString *src = _backing.string;
	NSUInteger len = src.length;
	if (len == 0) return;

	/* Reset everything to base attrs in one shot */
	[_backing setAttributes:_baseAttrs range:NSMakeRange(0, len)];

	if (!_language || _rules.keywordCount == 0) return;

	const char *buf = src.UTF8String;
	NSUInteger  byteLen = strlen(buf);

	void (^applyColor)(NSUInteger, NSUInteger, NSColor *) =
		^(NSUInteger start, NSUInteger end, NSColor *color) {
			NSString *sub = [[NSString alloc] initWithBytes:buf+start
			                                         length:end-start
			                                       encoding:NSUTF8StringEncoding];
			if (!sub) return;
			NSString *prefix = [[NSString alloc] initWithBytes:buf
			                                            length:start
			                                          encoding:NSUTF8StringEncoding];
			if (!prefix) return;
			NSUInteger charStart = prefix.length;
			NSUInteger charLen   = sub.length;
			if (charStart + charLen > len) return;
			[_backing addAttribute:NSForegroundColorAttributeName
			                 value:color
			                 range:NSMakeRange(charStart, charLen)];
		};

	/* Consume an identifier starting at byte offset.  If it matches a
	   keyword or type, color it accordingly and return.  Otherwise, if
	   memberColor is non-nil, apply that color (caller-determined).
	   Pass nil for standalone identifiers (no default coloring).     */
	void (^consumeIdentifier)(NSUInteger *, NSColor *) = ^(NSUInteger *pos, NSColor *memberColor) {
		NSUInteger start = *pos;
		(*pos)++;
		while (*pos < byteLen && (isalnum((unsigned char)buf[*pos]) || buf[*pos] == '_')) (*pos)++;
		NSUInteger wordLen = *pos - start;

		for (NSUInteger k = 0; k < _rules.keywordCount; k++) {
			NSUInteger klen = strlen(_rules.keywords[k]);
			if (klen == wordLen && memcmp(buf+start, _rules.keywords[k], klen) == 0) {
				applyColor(start, *pos, g_theme.keyword);
				return;
			}
		}
		for (NSUInteger k = 0; k < _rules.typeCount; k++) {
			NSUInteger klen = strlen(_rules.types[k]);
			if (klen == wordLen && memcmp(buf+start, _rules.types[k], klen) == 0) {
				applyColor(start, *pos, g_theme.type);
				return;
			}
		}
		if (memberColor)
			applyColor(start, *pos, memberColor);
	};

	NSUInteger i = 0;
	while (i < byteLen) {
		unsigned char c = (unsigned char)buf[i];

		/* ── Single-line comment ─────────────────────────────────────────── */
		if (!_rules.luaStyle && c == '/' && i+1 < byteLen && buf[i+1] == '/') {
			NSUInteger start = i;
			while (i < byteLen && buf[i] != '\n') i++;
			applyColor(start, i, g_theme.comment);
			continue;
		}
		/* Lua single-line:  -- */
		if (_rules.luaStyle && c == '-' && i+1 < byteLen && buf[i+1] == '-') {
			NSUInteger start = i;
			if (i+3 < byteLen && buf[i+2] == '[' && buf[i+3] == '[') {
				i += 4;
				while (i+1 < byteLen && !(buf[i] == ']' && buf[i+1] == ']')) i++;
				if (i+1 < byteLen) i += 2;
			} else {
				while (i < byteLen && buf[i] != '\n') i++;
			}
			applyColor(start, i, g_theme.comment);
			continue;
		}

		/* ── Block comment slash-star */
		if (!_rules.luaStyle && c == '/' && i+1 < byteLen && buf[i+1] == '*') {
			NSUInteger start = i;
			i += 2;
			while (i+1 < byteLen && !(buf[i] == '*' && buf[i+1] == '/')) i++;
			if (i+1 < byteLen) i += 2;
			applyColor(start, i, g_theme.comment);
			continue;
		}

		/* ── Preprocessor  # (C-family only) ──────────────────────────── */
		if (_rules.hasPreprocessor && c == '#'
		    && (i == 0 || buf[i-1] == '\n')) {
			NSUInteger start = i;
			while (i < byteLen) {
				if (buf[i] == '\n') {
					if (i > 0 && buf[i-1] == '\\') { i++; continue; }
					break;
				}
				i++;
			}
			applyColor(start, i, g_theme.preprocessor);
			continue;
		}

		/* ── String literal  " ─────────────────────────────────────────── */
		if (c == '"') {
			NSUInteger start = i++;
			while (i < byteLen && buf[i] != '"') {
				if (buf[i] == '\\') i++;
				i++;
			}
			if (i < byteLen) i++;
			applyColor(start, i, g_theme.string);
			continue;
		}
		/* ── String literal  ' (C char, Swift single-quoted) ──────────── */
		if (c == '\'') {
			NSUInteger start = i++;
			while (i < byteLen && buf[i] != '\'') {
				if (buf[i] == '\\') i++;
				i++;
			}
			if (i < byteLen) i++;
			applyColor(start, i, g_theme.string);
			continue;
		}
		/* ── Lua long string  [[ ]] ─────────────────────────────────────── */
		if (_rules.luaStyle && c == '[' && i+1 < byteLen && buf[i+1] == '[') {
			NSUInteger start = i;
			i += 2;
			while (i+1 < byteLen && !(buf[i] == ']' && buf[i+1] == ']')) i++;
			if (i+1 < byteLen) i += 2;
			applyColor(start, i, g_theme.string);
			continue;
		}

		/* ── Number literal ─────────────────────────────────────────────── */
		if (isdigit(c) || (c == '.' && i+1 < byteLen && isdigit((unsigned char)buf[i+1]))) {
			NSUInteger start = i;
			if (c == '0' && i+1 < byteLen && (buf[i+1]=='x'||buf[i+1]=='X')) {
				i += 2;
				while (i < byteLen && isxdigit((unsigned char)buf[i])) i++;
			} else {
				while (i < byteLen && (isdigit((unsigned char)buf[i]) || buf[i] == '.' ||
				       buf[i] == 'e' || buf[i] == 'E' || buf[i] == '_' ||
				       ((buf[i]=='+' || buf[i]=='-') && i>0 &&
				        (buf[i-1]=='e'||buf[i-1]=='E')))) i++;
				while (i < byteLen && (buf[i]=='f'||buf[i]=='u'||buf[i]=='l'||
				       buf[i]=='F'||buf[i]=='U'||buf[i]=='L')) i++;
			}
			applyColor(start, i, g_theme.number);
			continue;
		}

		/* ── Accessor: .identifier  /  Lua :method ────────────────────────────
		   Matches any . or (in Lua) : followed by an identifier, regardless of
		   what precedes it.  Handles table.field, obj:method(), "hello":upper()
		   and (expr).prop.  In C-family, : is ternary / labels and passes
		   through to the operator block below.
		   Edge cases consumed earlier:  `.5` (number literal), `..` (below).
		   The accessor itself is colored as an operator.                   */
		if (c == '.' || (_rules.luaStyle && c == ':')) {
			/* Lua concat  .. */
			if (c == '.' && i+1 < byteLen && buf[i+1] == '.') {
				applyColor(i, i+2, g_theme.operator);
				i += 2;
				continue;
			}
			/* Lua label  ::  (only when followed by an identifier) */
			if (_rules.luaStyle && c == ':' && i+1 < byteLen && buf[i+1] == ':') {
				NSUInteger start = i;
				i += 2;
				if (i < byteLen && (isalpha((unsigned char)buf[i]) || buf[i]=='_'))
					consumeIdentifier(&i, nil);
				applyColor(start, i, g_theme.operator);
				continue;
			}
			applyColor(i, i+1, g_theme.operator);
			i++;
			/* skip whitespace between accessor and member name */
			while (i < byteLen && isspace((unsigned char)buf[i])) i++;
			if (i < byteLen && (isalpha((unsigned char)buf[i]) || buf[i]=='_')) {
				/* Peek past identifier + whitespace for '(' to decide
				   whether this is a function call or a plain property. */
				NSUInteger peek = i;
				while (peek < byteLen && (isalnum((unsigned char)buf[peek]) || buf[peek]=='_')) peek++;
				while (peek < byteLen && isspace((unsigned char)buf[peek])) peek++;
				BOOL isCall = (peek < byteLen && buf[peek] == '(');

				NSColor *mc;
				if (isCall)
					mc = g_theme.functionCall;
				else
					mc = isupper((unsigned char)buf[i]) ? g_theme.type : g_theme.property;

				consumeIdentifier(&i, mc);
			}
			continue;
		}

		/* ── Identifier / keyword ───────────────────────────────────────── */
		if (isalpha(c) || c == '_' ||
		    (c == '@' && i+1 < byteLen && isalpha((unsigned char)buf[i+1]))) {
			consumeIdentifier(&i, nil);
			continue;
		}

		/* ── Operators ──────────────────────────────────────────────────── */
		if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%' ||
		    c == '=' || c == '<' || c == '>' || c == '!' || c == '&' ||
		    c == '|' || c == '^' || c == '~' || c == '?' || c == ':') {
			NSUInteger start = i++;
			if (i < byteLen && (buf[i]==buf[start]||buf[i]=='='||
			    (buf[start]=='-'&&buf[i]=='>')||
			    (buf[start]=='<'&&buf[i]=='<')||
			    (buf[start]=='>'&&buf[i]=='>'))) i++;
			applyColor(start, i, g_theme.operator);
			continue;
		}

		i++;
	}
}

/* processEditing is called by NSTextView after every edit */
- (void)processEditing {
	[super processEditing];
	/* Re-highlight only the dirty paragraph range for performance */
	NSRange edited = self.editedRange;
	if (edited.location == NSNotFound || self.string.length == 0) return;

	/* Expand to full lines */
	NSString *s = self.string;
	NSUInteger start = edited.location;
	NSUInteger end   = NSMaxRange(edited);
	while (start > 0 && [s characterAtIndex:start-1] != '\n') start--;
	while (end < s.length && [s characterAtIndex:end] != '\n') end++;

	/* For simplicity, full re-highlight.  Fast enough for typical source files. */
	[self highlight];
}

@end
