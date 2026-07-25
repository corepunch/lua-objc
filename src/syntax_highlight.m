#pragma mark - Syntax highlighting (NSTextStorage subclass)

/* Token kinds — order determines priority (first match wins inside each pass). */
typedef NS_ENUM(NSInteger, SyntaxToken) {
	SyntaxTokenComment,
	SyntaxTokenString,
	SyntaxTokenNumber,
	SyntaxTokenKeyword,
	SyntaxTokenType,
	SyntaxTokenPreprocessor,
	SyntaxTokenOperator,
};

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

static NSColor *g_colorComment;
static NSColor *g_colorString;
static NSColor *g_colorNumber;
static NSColor *g_colorKeyword;
static NSColor *g_colorType;
static NSColor *g_colorPreprocessor;
static NSColor *g_colorOperator;
static NSColor *g_colorDefault;

static void syntax_init_colors(void) {
	if (g_colorDefault) return;
	/* light / dark pairs (sRGB) */
	g_colorComment     = syntax_color(0.40f,0.47f,0.40f,  0.44f,0.54f,0.44f);
	g_colorString      = syntax_color(0.75f,0.12f,0.10f,  0.98f,0.40f,0.36f);
	g_colorNumber      = syntax_color(0.10f,0.40f,0.75f,  0.36f,0.72f,1.00f);
	g_colorKeyword     = syntax_color(0.62f,0.00f,0.57f,  0.92f,0.38f,0.90f);
	g_colorType        = syntax_color(0.10f,0.46f,0.65f,  0.29f,0.72f,0.88f);
	g_colorPreprocessor= syntax_color(0.50f,0.35f,0.00f,  0.80f,0.62f,0.18f);
	g_colorOperator    = syntax_color(0.30f,0.30f,0.30f,  0.65f,0.65f,0.65f);
	g_colorDefault     = [NSColor labelColor];
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
	syntax_init_colors();
	_font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
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

	/* We track byte offsets, then convert back to NSRange character offsets. */
	/* For ASCII-dominant source this is 1:1; for non-ASCII we use UTF-16 length. */

	/* Helper: apply color to a byte-range, converting to char range safely */
	void (^applyColor)(NSUInteger, NSUInteger, NSColor *) =
		^(NSUInteger start, NSUInteger end, NSColor *color) {
			NSString *sub = [[NSString alloc] initWithBytes:buf+start
			                                         length:end-start
			                                       encoding:NSUTF8StringEncoding];
			if (!sub) return;
			/* Find the character-level offset by slicing the prefix */
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

	NSUInteger i = 0;
	while (i < byteLen) {
		unsigned char c = (unsigned char)buf[i];

		/* ── Single-line comment ─────────────────────────────────────────── */
		if (!_rules.luaStyle && c == '/' && i+1 < byteLen && buf[i+1] == '/') {
			NSUInteger start = i;
			while (i < byteLen && buf[i] != '\n') i++;
			applyColor(start, i, g_colorComment);
			continue;
		}
		/* Lua single-line:  -- */
		if (_rules.luaStyle && c == '-' && i+1 < byteLen && buf[i+1] == '-') {
			/* Check for long comment  --[[ ]] */
			NSUInteger start = i;
			if (i+3 < byteLen && buf[i+2] == '[' && buf[i+3] == '[') {
				i += 4;
				while (i+1 < byteLen && !(buf[i] == ']' && buf[i+1] == ']')) i++;
				if (i+1 < byteLen) i += 2;
			} else {
				while (i < byteLen && buf[i] != '\n') i++;
			}
			applyColor(start, i, g_colorComment);
			continue;
		}

		/* ── Block comment slash-star */
		if (!_rules.luaStyle && c == '/' && i+1 < byteLen && buf[i+1] == '*') {
			NSUInteger start = i;
			i += 2;
			while (i+1 < byteLen && !(buf[i] == '*' && buf[i+1] == '/')) i++;
			if (i+1 < byteLen) i += 2;
			applyColor(start, i, g_colorComment);
			continue;
		}

		/* ── Swift // comment (same as C but no block needed separately) */
		/* already handled above */

		/* ── Preprocessor  # (C-family only) ──────────────────────────── */
		if (_rules.hasPreprocessor && c == '#'
		    && (i == 0 || buf[i-1] == '\n')) {
			NSUInteger start = i;
			/* handle line continuation with \ */
			while (i < byteLen) {
				if (buf[i] == '\n') {
					if (i > 0 && buf[i-1] == '\\') { i++; continue; }
					break;
				}
				i++;
			}
			applyColor(start, i, g_colorPreprocessor);
			continue;
		}

		/* ── ObjC @ keywords (already in keyword list, handled below) ─── */

		/* ── String literal  " ─────────────────────────────────────────── */
		if (c == '"') {
			NSUInteger start = i++;
			while (i < byteLen && buf[i] != '"') {
				if (buf[i] == '\\') i++;
				i++;
			}
			if (i < byteLen) i++;
			applyColor(start, i, g_colorString);
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
			applyColor(start, i, g_colorString);
			continue;
		}
		/* ── Lua long string  [[ ]] ─────────────────────────────────────── */
		if (_rules.luaStyle && c == '[' && i+1 < byteLen && buf[i+1] == '[') {
			NSUInteger start = i;
			i += 2;
			while (i+1 < byteLen && !(buf[i] == ']' && buf[i+1] == ']')) i++;
			if (i+1 < byteLen) i += 2;
			applyColor(start, i, g_colorString);
			continue;
		}

		/* ── Number literal ─────────────────────────────────────────────── */
		if (isdigit(c) || (c == '.' && i+1 < byteLen && isdigit((unsigned char)buf[i+1]))) {
			NSUInteger start = i;
			/* hex */
			if (c == '0' && i+1 < byteLen && (buf[i+1]=='x'||buf[i+1]=='X')) {
				i += 2;
				while (i < byteLen && isxdigit((unsigned char)buf[i])) i++;
			} else {
				while (i < byteLen && (isdigit((unsigned char)buf[i]) || buf[i] == '.' ||
				       buf[i] == 'e' || buf[i] == 'E' || buf[i] == '_' ||
				       ((buf[i]=='+' || buf[i]=='-') && i>0 &&
				        (buf[i-1]=='e'||buf[i-1]=='E')))) i++;
				/* suffix: f, u, l, ul, ll, etc. */
				while (i < byteLen && (buf[i]=='f'||buf[i]=='u'||buf[i]=='l'||
				       buf[i]=='F'||buf[i]=='U'||buf[i]=='L')) i++;
			}
			applyColor(start, i, g_colorNumber);
			continue;
		}

		/* ── Identifier / keyword ───────────────────────────────────────── */
		if (isalpha(c) || c == '_' ||
		    /* ObjC/Swift @ prefixed keywords */
		    (c == '@' && i+1 < byteLen && isalpha((unsigned char)buf[i+1]))) {
			NSUInteger start = i;
			i++;
			while (i < byteLen && (isalnum((unsigned char)buf[i]) || buf[i] == '_')) i++;
			NSUInteger wordLen = i - start;

			/* keyword lookup */
			NSColor *color = nil;
			for (NSUInteger k = 0; k < _rules.keywordCount && !color; k++) {
				NSUInteger klen = strlen(_rules.keywords[k]);
				if (klen == wordLen && memcmp(buf+start, _rules.keywords[k], klen) == 0)
					color = g_colorKeyword;
			}
			for (NSUInteger k = 0; k < _rules.typeCount && !color; k++) {
				NSUInteger klen = strlen(_rules.types[k]);
				if (klen == wordLen && memcmp(buf+start, _rules.types[k], klen) == 0)
					color = g_colorType;
			}
			if (color) applyColor(start, i, color);
			continue;
		}

		/* ── Operators ──────────────────────────────────────────────────── */
		if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%' ||
		    c == '=' || c == '<' || c == '>' || c == '!' || c == '&' ||
		    c == '|' || c == '^' || c == '~' || c == '?' || c == ':') {
			NSUInteger start = i++;
			/* absorb a second operator char if it forms a two-char op */
			if (i < byteLen && (buf[i]==buf[start]||buf[i]=='='||
			    (buf[start]=='-'&&buf[i]=='>')||
			    (buf[start]=='<'&&buf[i]=='<')||
			    (buf[start]=='>'&&buf[i]=='>'))) i++;
			applyColor(start, i, g_colorOperator);
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
