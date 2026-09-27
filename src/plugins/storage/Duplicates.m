// Duplicate files within folders the person chose (issue #37, item 17).
// Included by StorageScan.m.
//
// This is the one place Diskmap reads file contents, so it runs only on the
// roots it is given. Files are grouped by size, then by a SHA-256 of their
// first 4 KB, then by a SHA-256 of all their bytes; only files whose whole
// contents match are reported. Hard links (one file under two names) and
// files iCloud evicted (reading would download them) are never read.
//
// Deleting a duplicate frees only the blocks it does not share: APFS clones
// share their blocks, so each file's private size, not its size, is what a
// cleanup would recover.
#import <CommonCrypto/CommonDigest.h>

static const NSUInteger DuplicateHeadBytes = 4096;
static const NSUInteger DuplicateReadChunk = 1 << 20;
static const NSUInteger DuplicateGroupLimit = 500;

typedef struct { uint64_t inode; dev_t device; } DuplicateIdentity;

@interface DuplicateJob : NSObject
@property(atomic) BOOL cancelled;
@property NSArray<NSString *> *roots;
@property uint64_t minimumBytes;
@property NSUInteger examined, hashed;
@property uint64_t bytesRead;
@property NSMutableArray *issues;
@property NSDictionary *snapshot;
@property BOOL done;
@property NSString *stage;
@end

@implementation DuplicateJob
- (instancetype)init {
	if ((self = [super init])) { _issues = [NSMutableArray array]; _stage = @"Listing files"; }
	return self;
}
- (void)issue:(NSString *)path code:(int)code {
	if (self.issues.count < ScanIssueLimit) [self.issues addObject:@{@"path": path, @"reason": @(strerror(code))}];
}
// Every regular, local, non-empty file under a root, by size.
- (void)collect:(NSString *)root into:(NSMutableDictionary<NSNumber *, NSMutableArray *> *)bySize seen:(NSMutableSet *)seen {
	NSDirectoryEnumerator *walker = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:root]
		includingPropertiesForKeys:@[] options:0 errorHandler:^BOOL(NSURL *url, NSError *error) {
			[self issue:url.path code:(int)error.code]; return YES;
		}];
	for (NSURL *url in walker) {
		if (self.cancelled) return;
		struct stat st;
		if (lstat(url.fileSystemRepresentation, &st)) { [self issue:url.path code:errno]; continue; }
		if (S_ISDIR(st.st_mode) && (st.st_flags & SF_DATALESS)) { [walker skipDescendants]; continue; }
		if (!S_ISREG(st.st_mode) || (st.st_flags & SF_DATALESS) || (uint64_t)st.st_size < self.minimumBytes) continue;
		NSValue *identity = [NSValue valueWithBytes:&(DuplicateIdentity){(uint64_t)st.st_ino, st.st_dev} objCType:@encode(DuplicateIdentity)];
		if ([seen containsObject:identity]) continue;
		[seen addObject:identity];
		self.examined++;
		NSMutableArray *list = bySize[@(st.st_size)];
		if (!list) { list = [NSMutableArray array]; bySize[@(st.st_size)] = list; }
		[list addObject:url.path];
	}
}
// SHA-256 of the first `limit` bytes (0 for the whole file), hex encoded.
- (NSString *)hash:(NSString *)path limit:(NSUInteger)limit {
	int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
	if (fd < 0) { [self issue:path code:errno]; return nil; }
	fcntl(fd, F_NOCACHE, 1);
	CC_SHA256_CTX context; CC_SHA256_Init(&context);
	uint8_t *buffer = malloc(DuplicateReadChunk);
	uint64_t total = 0;
	BOOL failed = NO;
	while (!self.cancelled) {
		size_t want = limit ? MIN(DuplicateReadChunk, limit - total) : DuplicateReadChunk;
		if (want == 0) break;
		ssize_t count = read(fd, buffer, want);
		if (count < 0 && errno == EINTR) continue;
		if (count < 0) { [self issue:path code:errno]; failed = YES; break; }
		if (count == 0) break;
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		total += (uint64_t)count;
	}
	free(buffer); close(fd);
	self.bytesRead += total;
	if (failed || self.cancelled) return nil;
	uint8_t digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &context);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
	return hex;
}
// Groups paths by the hash of their first `limit` bytes; singletons drop out.
- (NSArray<NSArray *> *)split:(NSArray<NSString *> *)paths limit:(NSUInteger)limit {
	NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
	for (NSString *path in paths) {
		if (self.cancelled) return @[];
		NSString *digest = [self hash:path limit:limit];
		if (!digest) continue;
		self.hashed++;
		NSMutableArray *group = groups[digest] ?: [NSMutableArray array];
		[group addObject:path]; groups[digest] = group;
	}
	NSMutableArray *result = [NSMutableArray array];
	for (NSArray *group in groups.allValues) if (group.count > 1) [result addObject:group];
	return result;
}
// Bytes deleting this file would free: its blocks not shared with clones.
static uint64_t duplicatePrivateSize(NSString *path, uint64_t fallback) {
	struct attrlist attrs = {.bitmapcount = ATTR_BIT_MAP_COUNT, .forkattr = ATTR_CMNEXT_PRIVATESIZE};
	struct { uint32_t length; off_t size; } __attribute__((packed)) buffer;
	if (getattrlist(path.fileSystemRepresentation, &attrs, &buffer, sizeof(buffer), FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW) != 0)
		return fallback;
	return (uint64_t)MAX(0, buffer.size);
}
- (void)publish:(NSArray *)groups done:(BOOL)done {
	NSDictionary *snapshot = @{@"groups": groups ?: @[], @"examined": @(self.examined), @"hashed": @(self.hashed),
		@"bytesRead": @(self.bytesRead), @"issues": self.issues.copy, @"stage": self.stage,
		@"failure": self.cancelled ? @"Search cancelled." : @""};
	@synchronized(self) { self.snapshot = snapshot; self.done = done; }
}
- (void)run {
	@autoreleasepool {
		scanNeverMaterialize();
		NSMutableDictionary<NSNumber *, NSMutableArray *> *bySize = [NSMutableDictionary dictionary];
		NSMutableSet *seen = [NSMutableSet set];
		for (NSString *root in self.roots) [self collect:root into:bySize seen:seen];
		self.stage = @"Comparing contents";
		[self publish:nil done:NO];
		NSMutableArray *groups = [NSMutableArray array];
		// Largest first: they matter most, and the group limit keeps them.
		NSArray *sizes = [bySize.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
		for (NSNumber *size in sizes) {
			if (self.cancelled || groups.count >= DuplicateGroupLimit) break;
			NSArray *candidates = bySize[size];
			if (candidates.count < 2) continue;
			for (NSArray *head in [self split:candidates limit:DuplicateHeadBytes]) {
				NSArray *full = size.unsignedLongLongValue <= DuplicateHeadBytes ? @[head] : [self split:head limit:0];
				for (NSArray *group in full) {
					NSMutableArray *files = [NSMutableArray array];
					uint64_t reclaimable = 0;
					for (NSString *path in [group sortedArrayUsingSelector:@selector(compare:)]) {
						uint64_t privateBytes = duplicatePrivateSize(path, size.unsignedLongLongValue);
						[files addObject:@{@"path": path, @"privateBytes": @(privateBytes)}];
					}
					// Keeping one copy, the others' private bytes are what goes.
					for (NSUInteger i = 1; i < files.count; i++) reclaimable += [files[i][@"privateBytes"] unsignedLongLongValue];
					[groups addObject:@{@"bytes": size, @"files": files, @"reclaimable": @(reclaimable)}];
				}
			}
			[self publish:groups done:NO];
		}
		self.stage = @"Done";
		[self publish:groups done:YES];
	}
}
@end

static const char *DuplicateMetatable = "StorageScan.Duplicates";

static DuplicateJob *newDuplicateJob(lua_State *L) {
	validatePaths(L, 1);
	DuplicateJob *job = [DuplicateJob new];
	job.roots = paths(L, 1);
	if (lua_istable(L, 2)) {
		lua_getfield(L, 2, "minimumBytes");
		job.minimumBytes = (uint64_t)MAX(1, luaL_optnumber(L, -1, 1)); lua_pop(L, 1);
	} else {
		job.minimumBytes = 1;
	}
	return job;
}
static DuplicateJob *checkDuplicateJob(lua_State *L) {
	CFTypeRef *ref = luaL_checkudata(L, 1, DuplicateMetatable);
	if (!*ref) luaL_error(L, "duplicate search already collected");
	return (__bridge DuplicateJob *)*ref;
}
// duplicatesStart(roots, {minimumBytes}) -> handle
static int duplicatesStart(lua_State *L) {
	DuplicateJob *job = newDuplicateJob(L);
	CFTypeRef *ref = lua_newuserdatauv(L, sizeof(CFTypeRef), 0);
	*ref = CFBridgingRetain(job);
	luaL_setmetatable(L, DuplicateMetatable);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [job run]; });
	return 1;
}
// duplicates(roots, options) -> result, synchronously (tests).
static int duplicates(lua_State *L) {
	DuplicateJob *job = newDuplicateJob(L);
	[job run];
	pushValue(L, job.snapshot);
	return 1;
}
static int duplicatesPoll(lua_State *L) {
	DuplicateJob *job = checkDuplicateJob(L); NSDictionary *snapshot; BOOL done;
	@synchronized(job) { snapshot = job.snapshot; done = job.done; }
	lua_pushboolean(L, done);
	if (snapshot) pushValue(L, snapshot); else lua_pushnil(L);
	return 2;
}
static int duplicatesCancel(lua_State *L) { checkDuplicateJob(L).cancelled = YES; return 0; }
static int duplicatesCollect(lua_State *L) {
	CFTypeRef *ref = luaL_checkudata(L, 1, DuplicateMetatable);
	if (*ref) { ((__bridge DuplicateJob *)*ref).cancelled = YES; CFRelease(*ref); *ref = NULL; }
	return 0;
}
