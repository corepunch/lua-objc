// A standalone Lua service plugin: no second UI runtime or Lua callbacks on workers.
// Native bulk metadata enumeration and cancellation cannot be expressed by KVC.
#import <Foundation/Foundation.h>
#import <sys/attr.h>
#import <sys/vnode.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <dlfcn.h>
#import <lua.h>
#import <lauxlib.h>

static const NSUInteger ScanBufferSize = 64 * 1024;
static const NSUInteger ScanIssueLimit = 1000;
static const NSUInteger ScanDepthLimit = 256;
static const NSTimeInterval ScanTimeout = 600;

// getattrlistbulk packs fields on four-byte boundaries, including 64-bit sizes.
#pragma pack(push, 4)
typedef struct {
	uint32_t length;
	attribute_set_t returned;
	uint32_t error;
	attrreference_t name;
	fsobj_type_t type;
	uint64_t inode;
	off_t allocated;
} ScanEntry;
#pragma pack(pop)

typedef struct { uint64_t inode; dev_t device; } ScanIdentity;
@interface StorageScanJob : NSObject {
	ScanIdentity *_seen;
	NSUInteger _seenCount, _seenCapacity;
}
@property(atomic) BOOL cancelled;
@property NSArray<NSString *> *roots;
@property NSSet<NSString *> *exclusions;
@property NSMutableArray *trees;
@property NSMutableArray *states;
@property NSMutableArray *issues;
@property NSUInteger errors, visited, bulkCalls;
@property NSTimeInterval started;
@property NSString *failure;
@property NSDictionary *snapshot;
@property BOOL done;
- (void)run;
- (void)publish:(BOOL)done;
@end

@implementation StorageScanJob
- (instancetype)init {
	if ((self = [super init])) {
		_trees = [NSMutableArray array]; _states = [NSMutableArray array]; _issues = [NSMutableArray array];
		_failure = @"";
	}
	return self;
}
- (void)dealloc { free(_seen); }
static NSUInteger identityHash(ScanIdentity key) {
	uint64_t x = key.inode ^ ((uint64_t)(uint32_t)key.device << 32);
	x = (x ^ (x >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
	x = (x ^ (x >> 27)) * UINT64_C(0x94d049bb133111eb);
	return x ^ (x >> 31);
}
- (BOOL)seenInode:(uint64_t)inode device:(dev_t)device {
	if (!inode) { self.failure = @"Filesystem returned an invalid file identity."; return YES; }
	if (!_seenCapacity || (_seenCount + 1) * 2 >= _seenCapacity) {
		NSUInteger capacity = _seenCapacity ? _seenCapacity * 2 : 4096;
		ScanIdentity *table = calloc(capacity, sizeof(ScanIdentity));
		if (!table) { self.failure = @"Not enough memory to track file identities."; return YES; }
		for (NSUInteger i = 0; i < _seenCapacity; i++) if (_seen[i].inode) {
			NSUInteger slot = identityHash(_seen[i]) & (capacity - 1);
			while (table[slot].inode) slot = (slot + 1) & (capacity - 1);
			table[slot] = _seen[i];
		}
		free(_seen); _seen = table; _seenCapacity = capacity;
	}
	ScanIdentity key = {inode, device};
	NSUInteger slot = identityHash(key) & (_seenCapacity - 1);
	while (_seen[slot].inode) {
		if (_seen[slot].inode == inode && _seen[slot].device == device) return YES;
		slot = (slot + 1) & (_seenCapacity - 1);
	}
	_seen[slot] = key; _seenCount++;
	return NO;
}
- (void)issue:(NSString *)path code:(int)code {
	self.errors++;
	if (self.issues.count < ScanIssueLimit) [self.issues addObject:@{@"path": path, @"reason": @(strerror(code))}];
}
- (BOOL)stopped {
	if (self.cancelled || self.failure.length) return YES;
	if (NSProcessInfo.processInfo.systemUptime - self.started > ScanTimeout) {
		self.failure = @"Scan exceeded ten minutes."; return YES;
	}
	return NO;
}
- (uint64_t)directory:(int)fd path:(NSString *)path device:(dev_t)device depth:(NSUInteger)depth {
	if ([self stopped]) return 0;
	if (depth > ScanDepthLimit) { [self issue:path code:ELOOP]; return 0; }
	struct stat st;
	if (fstat(fd, &st)) { [self issue:path code:errno]; return 0; }
	if (st.st_dev != device) return 0;
	self.visited++;
	if ([self seenInode:st.st_ino device:device]) return 0;
	uint64_t bytes = (uint64_t)st.st_blocks * 512;
	void *buffer = malloc(ScanBufferSize);
	if (!buffer) { self.failure = @"Not enough memory for directory metadata."; return bytes; }
	struct attrlist attrs = {.bitmapcount = ATTR_BIT_MAP_COUNT,
		.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_ERROR | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID,
		.fileattr = ATTR_FILE_ALLOCSIZE};
	while (![self stopped]) {
		int count = getattrlistbulk(fd, &attrs, buffer, ScanBufferSize, FSOPT_PACK_INVAL_ATTRS);
		self.bulkCalls++;
		if (count <= 0) { if (count < 0) [self issue:path code:errno]; break; }
		char *cursor = buffer, *end = cursor + ScanBufferSize;
		for (int i = 0; i < count && ![self stopped]; i++) { @autoreleasepool {
			if (end - cursor < offsetof(ScanEntry, allocated)) { [self issue:path code:EIO]; break; }
			ScanEntry entry = {0}; memcpy(&entry, cursor, offsetof(ScanEntry, allocated));
			NSUInteger fixedSize = entry.type == VREG ? sizeof(entry) : offsetof(ScanEntry, allocated);
			if (entry.length < fixedSize || entry.length > end - cursor) { [self issue:path code:EIO]; break; }
			int64_t nameOffset = offsetof(ScanEntry, name) + (int64_t)entry.name.attr_dataoffset;
			if (!(entry.returned.commonattr & ATTR_CMN_NAME) || nameOffset < fixedSize ||
				entry.name.attr_length < 1 || nameOffset + entry.name.attr_length > entry.length) { [self issue:path code:EIO]; cursor += entry.length; continue; }
			if (entry.type == VREG) memcpy(&entry.allocated, cursor + offsetof(ScanEntry, allocated), sizeof(entry.allocated));
			const char *name = cursor + nameOffset;
			if (name[entry.name.attr_length - 1] != '\0' || strchr(name, '/')) { [self issue:path code:EIO]; cursor += entry.length; continue; }
			NSString *component = [[NSString alloc] initWithBytes:name length:strlen(name) encoding:NSUTF8StringEncoding];
			NSString *child = [path stringByAppendingPathComponent:component ?: @"<invalid filename>"];
			cursor += entry.length;
			if (!strcmp(name, ".") || !strcmp(name, "..") || [self.exclusions containsObject:child]) continue;
			if (entry.error) { [self issue:child code:entry.error]; continue; }
			if (!(entry.returned.commonattr & ATTR_CMN_OBJTYPE)) { [self issue:child code:ENOTSUP]; continue; }
			if (entry.type == VDIR) {
				int childFD = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
				if (childFD < 0) { [self issue:child code:errno]; continue; }
				bytes += [self directory:childFD path:child device:device depth:depth + 1]; close(childFD);
			} else if (entry.type == VREG) {
				uint64_t inode = entry.inode; off_t allocated = entry.allocated;
				if (!(entry.returned.commonattr & ATTR_CMN_FILEID) || !(entry.returned.fileattr & ATTR_FILE_ALLOCSIZE)) {
					struct stat fileStat;
					if (fstatat(fd, name, &fileStat, AT_SYMLINK_NOFOLLOW)) { [self issue:child code:errno]; continue; }
					if (!S_ISREG(fileStat.st_mode) || fileStat.st_dev != device) continue;
					inode = fileStat.st_ino; allocated = fileStat.st_blocks * 512;
				}
				self.visited++;
				if (allocated < 0) { [self issue:child code:EIO]; continue; }
				if (![self seenInode:inode device:device]) bytes += (uint64_t)allocated;
			}
		} }
	}
	free(buffer); return bytes;
}
- (void)root:(NSString *)path {
	NSString *state = nil; NSDictionary *tree = nil;
	NSArray *parts = path.pathComponents;
	int parent = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	const char *name = parts.count == 1 ? "." : [parts.lastObject fileSystemRepresentation];
	NSUInteger before = self.errors;
	// Resolve every ancestor through an open descriptor so symlinks cannot redirect roots.
	for (NSUInteger i = 1; parent >= 0 && i + 1 < parts.count; i++) {
		const char *part = [parts[i] fileSystemRepresentation];
		int next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
		if (next < 0) {
			int code = errno; struct stat link;
			if (!fstatat(parent, part, &link, AT_SYMLINK_NOFOLLOW) && S_ISLNK(link.st_mode)) state = @"skipped";
			else if (code == ENOENT) state = @"missing";
			else { state = @"unreadable"; [self issue:path code:code]; }
		}
		close(parent); parent = next;
	}
	if (parent >= 0) {
		struct stat st;
		if (fstatat(parent, name, &st, AT_SYMLINK_NOFOLLOW)) {
			int code = errno; state = code == ENOENT ? @"missing" : @"unreadable";
			if (code != ENOENT) [self issue:path code:code];
		} else if (S_ISDIR(st.st_mode)) {
			int fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
			uint64_t bytes = 0;
			if (fd < 0) [self issue:path code:errno];
			else { bytes = [self directory:fd path:path device:st.st_dev depth:0]; close(fd); }
			tree = @{@"kb": @(bytes / 1024.0), @"partial": @(self.errors > before)};
		} else if (S_ISREG(st.st_mode)) {
			self.visited++;
			tree = @{@"kb": @([self seenInode:st.st_ino device:st.st_dev] ? 0 : st.st_blocks / 2.0)};
		} else state = @"skipped";
		close(parent);
	} else if (!state) { state = @"unreadable"; [self issue:path code:errno]; }
	// A cancelled or timed-out root never becomes a complete measurement.
	if ([self stopped]) return;
	[self.trees addObject:tree ?: NSNull.null];
	[self.states addObject:state ?: (self.errors > before ? @"unreadable" : @"measured")];
}
- (void)publish:(BOOL)done {
	NSDictionary *snapshot = @{@"trees": self.trees.copy, @"rootStates": self.states.copy,
		@"completed": @(self.states.count), @"total": @(self.roots.count), @"issues": self.issues.copy,
		@"errors": @(self.errors), @"visited": @(self.visited), @"bulkCalls": @(self.bulkCalls),
		@"seconds": @(NSProcessInfo.processInfo.systemUptime - self.started),
		@"failure": self.cancelled ? @"Measurement cancelled." : self.failure};
	@synchronized(self) { self.snapshot = snapshot; self.done = done; }
}
- (void)run {
	@autoreleasepool {
		self.started = NSProcessInfo.processInfo.systemUptime;
		@try {
			for (NSString *path in self.roots) {
				if ([self stopped]) break;
				@autoreleasepool { [self root:path]; [self publish:NO]; }
			}
		} @catch (NSException *exception) { self.failure = exception.reason ?: @"Native scan failed."; }
		[self publish:YES];
		free(_seen); _seen = NULL; _seenCount = 0; _seenCapacity = 0;
	}
}
@end

static void pushValue(lua_State *L, id value) {
	if (!value || value == NSNull.null) { lua_pushnil(L); return; }
	if ([value isKindOfClass:NSString.class]) lua_pushstring(L, [value UTF8String]);
	else if ([value isKindOfClass:NSNumber.class]) {
		if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) lua_pushboolean(L, [value boolValue]);
		else lua_pushnumber(L, [value doubleValue]);
	} else if ([value isKindOfClass:NSArray.class]) {
		lua_createtable(L, (int)[value count], 0); NSUInteger i = 1;
		for (id child in value) { pushValue(L, child); lua_rawseti(L, -2, i++); }
	} else {
		lua_createtable(L, 0, (int)[value count]);
		for (NSString *key in value) { pushValue(L, value[key]); lua_setfield(L, -2, key.UTF8String); }
	}
}
static void validatePaths(lua_State *L, int index) {
	luaL_checktype(L, index, LUA_TTABLE);
	// Validate before retaining Foundation objects: luaL_error performs a longjmp.
	NSUInteger count = lua_rawlen(L, index);
	for (NSUInteger i = 1; i <= count; i++) {
		lua_rawgeti(L, index, i); size_t length; const char *text = luaL_checklstring(L, -1, &length);
		BOOL valid;
		@autoreleasepool {
			NSString *path = [[NSString alloc] initWithBytes:text length:length encoding:NSUTF8StringEncoding];
			NSArray *parts = [path componentsSeparatedByString:@"/"];
			valid = length && text[0] == '/' && !memchr(text, 0, length) && path &&
				![parts containsObject:@".."] && ![parts containsObject:@"."];
		}
		lua_pop(L, 1); luaL_argcheck(L, valid, index, "paths must be absolute UTF-8 strings without NUL or dot components");
	}
}
static NSArray *paths(lua_State *L, int index) {
	NSUInteger count = lua_rawlen(L, index);
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
	for (NSUInteger i = 1; i <= count; i++) {
		lua_rawgeti(L, index, i); NSString *path = @(lua_tostring(L, -1)); lua_pop(L, 1);
		// Standardize lexical separators, never resolve symlinks.
		NSArray *parts = path.pathComponents;
		[result addObject:[NSString pathWithComponents:parts]];
	}
	return result;
}
static StorageScanJob *newJob(lua_State *L) {
	validatePaths(L, 1);
	if (!lua_isnoneornil(L, 2)) validatePaths(L, 2);
	NSArray *roots = paths(L, 1);
	NSArray *excluded = lua_isnoneornil(L, 2) ? @[] : paths(L, 2);
	StorageScanJob *job = [StorageScanJob new]; job.roots = roots; job.exclusions = [NSSet setWithArray:excluded];
	return job;
}
static const char *JobMetatable = "StorageScan.Job";
static StorageScanJob *checkJob(lua_State *L) {
	CFTypeRef *ref = luaL_checkudata(L, 1, JobMetatable);
	luaL_argcheck(L, *ref != NULL, 1, "scan job has been released");
	return (__bridge StorageScanJob *)*ref;
}
static int start(lua_State *L) {
	StorageScanJob *job = newJob(L);
	CFTypeRef *ref = lua_newuserdatauv(L, sizeof(CFTypeRef), 0); *ref = CFBridgingRetain(job);
	luaL_setmetatable(L, JobMetatable);
	// Category values are awaiting this result in the foreground window.
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [job run]; });
	return 1;
}
static int scan(lua_State *L) { StorageScanJob *job = newJob(L); [job run]; pushValue(L, job.snapshot); return 1; }
static int poll(lua_State *L) {
	StorageScanJob *job = checkJob(L); NSDictionary *snapshot; BOOL done;
	@synchronized(job) { snapshot = job.snapshot; done = job.done; }
	lua_pushboolean(L, done); pushValue(L, snapshot); return 2;
}
static int cancel(lua_State *L) { checkJob(L).cancelled = YES; return 0; }
static int collect(lua_State *L) {
	CFTypeRef *ref = luaL_checkudata(L, 1, JobMetatable);
	if (*ref) { ((__bridge StorageScanJob *)*ref).cancelled = YES; CFRelease(*ref); *ref = NULL; }
	return 0;
}
int luaopen_StorageScan(lua_State *L) {
	// Lua can close while a cancelled worker is finishing a filesystem call.
	// Keep the code image mapped until process exit; workers retain no Lua state.
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Dl_info image;
		if (dladdr((const void *)&luaopen_StorageScan, &image)) dlopen(image.dli_fname, RTLD_NOW | RTLD_NODELETE);
	});
	luaL_newmetatable(L, JobMetatable);
	lua_pushcfunction(L, collect); lua_setfield(L, -2, "__gc"); lua_pop(L, 1);
	const luaL_Reg functions[] = {{"start", start}, {"poll", poll}, {"cancel", cancel}, {"scan", scan}, {NULL, NULL}};
	luaL_newlib(L, functions); lua_pushliteral(L, "getattrlistbulk"); lua_setfield(L, -2, "backend");
	return 1;
}
