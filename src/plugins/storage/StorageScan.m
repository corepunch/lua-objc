// A standalone Lua service plugin: no second UI runtime or Lua callbacks on workers.
// Native bulk metadata enumeration and cancellation cannot be expressed by KVC.
#import <Foundation/Foundation.h>
#import <sys/attr.h>
#import <sys/vnode.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <math.h>
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
@property BOOL exporting;
@property BOOL exportWriteFailed;
@property int exportFD;
@property NSString *exportPath;
@property NSString *exportTemporaryPath;
@property NSDictionary<NSString *, NSString *> *logicalRoots;
@property uint64_t capacityBytes, availableBytes;
@property NSUInteger exportedFiles;
- (void)run;
- (void)publish:(BOOL)done;
@end

@implementation StorageScanJob
- (instancetype)init {
	if ((self = [super init])) {
		_trees = [NSMutableArray array]; _states = [NSMutableArray array]; _issues = [NSMutableArray array];
		_failure = @""; _exportFD = -1;
	}
	return self;
}
- (void)dealloc { free(_seen); if (_exportFD >= 0) close(_exportFD); }
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
- (BOOL)writeExportData:(NSData *)data {
	const uint8_t *cursor = data.bytes;
	size_t remaining = data.length;
	while (remaining) {
		ssize_t written = write(self.exportFD, cursor, remaining);
		if (written < 0 && errno == EINTR) continue;
		if (written <= 0) {
			self.exportWriteFailed = YES;
			self.failure = [NSString stringWithFormat:@"Could not write the local mock snapshot: %s", strerror(errno)];
			return NO;
		}
		cursor += written; remaining -= (size_t)written;
	}
	return YES;
}
- (BOOL)exportFile:(NSString *)path allocated:(uint64_t)allocated counted:(uint64_t)counted {
	if (!self.exporting || self.exportWriteFailed) return NO;
	NSDictionary *entry = @{@"path": path, @"allocatedBytes": @(allocated), @"countedBytes": @(counted)};
	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:NSJSONWritingFragmentsAllowed error:&error];
	if (!data) {
		self.exportWriteFailed = YES;
		self.failure = [NSString stringWithFormat:@"Could not encode a file name for the local mock snapshot: %@", error.localizedDescription ?: @"invalid metadata"];
		return NO;
	}
	if (self.exportedFiles && ![self writeExportData:[@"," dataUsingEncoding:NSUTF8StringEncoding]]) return NO;
	if (![self writeExportData:data]) return NO;
	self.exportedFiles++;
	return YES;
}
- (void)finishExport {
	if (!self.exporting || self.exportFD < 0) return;
	BOOL partial = self.errors > 0 || self.failure.length > 0 || self.cancelled;
	NSString *footer = [NSString stringWithFormat:@"],\"partial\":%@,\"errors\":%lu,\"visited\":%lu}",
		partial ? @"true" : @"false", (unsigned long)self.errors, (unsigned long)self.visited];
	if (!self.exportWriteFailed && ![self writeExportData:[footer dataUsingEncoding:NSUTF8StringEncoding]]) self.exportWriteFailed = YES;
	if (!self.exportWriteFailed && fsync(self.exportFD) != 0) {
		self.exportWriteFailed = YES;
		self.failure = [NSString stringWithFormat:@"Could not flush the local mock snapshot: %s", strerror(errno)];
	}
	if (close(self.exportFD) != 0 && !self.exportWriteFailed) {
		self.exportWriteFailed = YES;
		self.failure = [NSString stringWithFormat:@"Could not close the local mock snapshot: %s", strerror(errno)];
	}
	self.exportFD = -1;
	if (!self.exportWriteFailed && rename(self.exportTemporaryPath.fileSystemRepresentation, self.exportPath.fileSystemRepresentation) != 0) {
		self.exportWriteFailed = YES;
		self.failure = [NSString stringWithFormat:@"Could not publish the local mock snapshot: %s", strerror(errno)];
	}
	if (self.exportWriteFailed) unlink(self.exportTemporaryPath.fileSystemRepresentation);
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
				BOOL alreadyCounted = [self seenInode:inode device:device];
				uint64_t fileBytes = (uint64_t)allocated;
				if (!alreadyCounted) bytes += fileBytes;
				[self exportFile:child allocated:fileBytes counted:alreadyCounted ? 0 : fileBytes];
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
			NSString *logicalPath = self.logicalRoots[path] ?: path;
			if (fd < 0) [self issue:path code:errno];
			else { bytes = [self directory:fd path:logicalPath device:st.st_dev depth:0]; close(fd); }
			tree = @{@"kb": @(bytes / 1024.0), @"partial": @(self.errors > before)};
		} else if (S_ISREG(st.st_mode)) {
			self.visited++;
			BOOL alreadyCounted = [self seenInode:st.st_ino device:st.st_dev];
			uint64_t fileBytes = (uint64_t)st.st_blocks * 512;
			NSString *logicalPath = self.logicalRoots[path] ?: path;
			[self exportFile:logicalPath allocated:fileBytes counted:alreadyCounted ? 0 : fileBytes];
			tree = @{@"kb": @(alreadyCounted ? 0 : fileBytes / 1024.0)};
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
		@"failure": self.cancelled ? @"Measurement cancelled." : self.failure,
		@"exportedFiles": @(self.exportedFiles), @"exportPath": self.exportPath ?: @"",
		@"partial": @(self.errors > 0 || self.failure.length > 0 || self.cancelled)};
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
		[self finishExport];
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
// NSTask's launch/error and pipe lifetime cannot be represented by KVC alone.
// Commands are argv arrays (never a shell) and workers never enter Lua.
@interface StorageCommandJob : NSObject
@property NSTask *task;
@property NSDictionary *result;
@property BOOL done;
@end
@implementation StorageCommandJob
@end
static const char *CommandMetatable = "StorageScan.Command";
static int commandStart(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSUInteger count = lua_rawlen(L, 1);
	luaL_argcheck(L, count > 0, 1, "expected executable and arguments");
	for (NSUInteger i = 1; i <= count; i++) {
		lua_rawgeti(L, 1, i); size_t length; const char *value = luaL_checklstring(L, -1, &length);
		BOOL valid = !memchr(value, 0, length) && [[NSString alloc] initWithBytes:value length:length encoding:NSUTF8StringEncoding] != nil;
		luaL_argcheck(L, valid, 1, "arguments must be UTF-8 without NUL"); lua_pop(L, 1);
	}
	NSMutableArray *arguments = [NSMutableArray array];
	for (NSUInteger i = 1; i <= count; i++) { lua_rawgeti(L, 1, i); [arguments addObject:@(lua_tostring(L, -1))]; lua_pop(L, 1); }
	StorageCommandJob *job = [StorageCommandJob new];
	job.task = [NSTask new]; job.task.executableURL = [NSURL fileURLWithPath:arguments.firstObject];
	[arguments removeObjectAtIndex:0]; job.task.arguments = arguments;
	CFTypeRef *ref = lua_newuserdatauv(L, sizeof(CFTypeRef), 0); *ref = CFBridgingRetain(job); luaL_setmetatable(L, CommandMetatable);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		@autoreleasepool {
			NSPipe *pipe = [NSPipe pipe]; job.task.standardOutput = pipe; job.task.standardError = pipe;
			NSError *error;
			if (![job.task launchAndReturnError:&error]) {
				@synchronized(job) { job.result = @{@"ok": @NO, @"output": error.localizedDescription}; job.done = YES; }
				return;
			}
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
				if (job.task.running) [job.task terminate];
			});
			NSMutableData *data = [NSMutableData data]; BOOL overflow = NO;
			while (YES) {
				NSData *chunk = [pipe.fileHandleForReading availableData]; if (!chunk.length) break;
				if (data.length + chunk.length <= 8 * 1024 * 1024) [data appendData:chunk]; else { overflow = YES; if (job.task.running) [job.task terminate]; }
			}
			[job.task waitUntilExit];
			NSString *output = overflow ? @"Command output exceeded the limit." : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Invalid command output.";
			@synchronized(job) { job.result = @{@"ok": @(!overflow && job.task.terminationStatus == 0), @"output": output}; job.done = YES; }
		}
	});
	return 1;
}
static int commandPoll(lua_State *L) {
	CFTypeRef *ref = luaL_checkudata(L, 1, CommandMetatable);
	StorageCommandJob *job = (__bridge StorageCommandJob *)*ref;
	@synchronized(job) { lua_pushboolean(L, job.done); pushValue(L, job.result); }
	return 2;
}
static int commandCollect(lua_State *L) {
	CFTypeRef *ref = luaL_checkudata(L, 1, CommandMetatable);
	if (*ref) { CFRelease(*ref); *ref = NULL; }
	return 0;
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
static NSString *absolutePathArgument(lua_State *L, int index, int argument) {
	size_t length = 0;
	const char *text = luaL_checklstring(L, index, &length);
	NSString *path = [[NSString alloc] initWithBytes:text length:length encoding:NSUTF8StringEncoding];
	NSArray *parts = [path componentsSeparatedByString:@"/"];
	BOOL valid = length && text[0] == '/' && !memchr(text, 0, length) && path &&
		![parts containsObject:@".."] && ![parts containsObject:@"."];
	luaL_argcheck(L, valid, argument, "path must be an absolute UTF-8 string without NUL or dot components");
	return [NSString pathWithComponents:path.pathComponents];
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
static int exportStart(lua_State *L) {
	StorageScanJob *job = newJob(L);
	NSString *outputPath = absolutePathArgument(L, 3, 3);
	luaL_argcheck(L, outputPath.length > 1, 3, "snapshot output path cannot be the filesystem root");
	luaL_checktype(L, 4, LUA_TTABLE);
	lua_getfield(L, 4, "capacityBytes");
	double capacity = luaL_checknumber(L, -1); lua_pop(L, 1);
	lua_getfield(L, 4, "availableBytes");
	double available = luaL_checknumber(L, -1); lua_pop(L, 1);
	luaL_argcheck(L, isfinite(capacity) && capacity >= 0 && capacity <= 9007199254740991.0 && floor(capacity) == capacity,
		4, "capacityBytes must be a nonnegative integer no larger than 2^53");
	luaL_argcheck(L, isfinite(available) && available >= 0 && available <= 9007199254740991.0 && floor(available) == available,
		4, "availableBytes must be a nonnegative integer no larger than 2^53");
	NSMutableDictionary *logicalRoots = [NSMutableDictionary dictionary];
	lua_getfield(L, 4, "logicalRoots");
	if (!lua_isnil(L, -1)) {
		luaL_checktype(L, -1, LUA_TTABLE);
		int mappings = lua_gettop(L);
		lua_pushnil(L);
		while (lua_next(L, mappings)) {
			luaL_checktype(L, -2, LUA_TSTRING); luaL_checktype(L, -1, LUA_TSTRING);
			NSString *physical = absolutePathArgument(L, -2, 4);
			NSString *logical = absolutePathArgument(L, -1, 4);
			luaL_argcheck(L, [job.roots containsObject:physical], 4, "logicalRoots keys must also be scan roots");
			logicalRoots[physical] = logical;
			lua_pop(L, 1);
		}
	}
	lua_pop(L, 1);
	job.exportPath = outputPath;
	job.logicalRoots = logicalRoots.copy;
	job.capacityBytes = (uint64_t)capacity;
	job.availableBytes = (uint64_t)available;
	NSString *template = [outputPath stringByAppendingString:@".tmp.XXXXXX"];
	char *temporary = strdup(template.fileSystemRepresentation);
	int fd = temporary ? mkstemp(temporary) : -1;
	if (fd < 0) {
		int code = errno ?: ENOMEM; free(temporary);
		return luaL_error(L, "Could not create a private snapshot file: %s", strerror(code));
	}
	job.exportTemporaryPath = @(temporary);
	free(temporary);
	job.exportFD = fd; job.exporting = YES;
	if (fchmod(fd, S_IRUSR | S_IWUSR) != 0) {
		int code = errno; close(fd); job.exportFD = -1; unlink(job.exportTemporaryPath.fileSystemRepresentation);
		return luaL_error(L, "Could not protect the local snapshot file: %s", strerror(code));
	}
	NSMutableSet *exclusions = [job.exclusions mutableCopy];
	[exclusions addObject:outputPath]; [exclusions addObject:job.exportTemporaryPath];
	job.exclusions = exclusions.copy;
	NSString *header = [NSString stringWithFormat:@"{\"format\":1,\"capacityBytes\":%llu,\"availableBytes\":%llu,\"items\":[",
		(unsigned long long)job.capacityBytes, (unsigned long long)job.availableBytes];
	if (![job writeExportData:[header dataUsingEncoding:NSUTF8StringEncoding]]) {
		NSString *failure = job.failure; close(job.exportFD); job.exportFD = -1;
		unlink(job.exportTemporaryPath.fileSystemRepresentation);
		return luaL_error(L, "%s", failure.UTF8String);
	}
	CFTypeRef *ref = lua_newuserdatauv(L, sizeof(CFTypeRef), 0); *ref = CFBridgingRetain(job);
	luaL_setmetatable(L, JobMetatable);
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
	luaL_newmetatable(L, CommandMetatable);
	lua_pushcfunction(L, commandCollect); lua_setfield(L, -2, "__gc"); lua_pop(L, 1);
	luaL_newmetatable(L, JobMetatable);
	lua_pushcfunction(L, collect); lua_setfield(L, -2, "__gc"); lua_pop(L, 1);
	const luaL_Reg functions[] = {{"commandStart", commandStart}, {"commandPoll", commandPoll}, {"start", start}, {"exportStart", exportStart}, {"poll", poll}, {"cancel", cancel}, {"scan", scan}, {NULL, NULL}};
	luaL_newlib(L, functions); lua_pushliteral(L, "getattrlistbulk"); lua_setfield(L, -2, "backend");
	return 1;
}
