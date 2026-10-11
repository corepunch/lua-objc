// A standalone Lua service plugin: no second UI runtime or Lua callbacks on workers.
// Native bulk metadata enumeration and cancellation cannot be expressed by KVC.
#import <Foundation/Foundation.h>
#import <sys/mount.h>
#import <sys/attr.h>
#import <sys/vnode.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <math.h>
#import <unistd.h>
#import <dlfcn.h>
#import <lua.h>
#import <lauxlib.h>
#import <os/lock.h>
#import <sys/resource.h>

static const NSUInteger ScanBufferSize = 64 * 1024;
static const NSUInteger ScanIssueLimit = 1000;
static const NSUInteger ScanDepthLimit = 256;
static const NSTimeInterval ScanTimeout = 600;
// Summaries are bounded so a disk with millions of files still publishes a
// small result: a ranked list of large files and one row per extension.
static const NSUInteger ScanFileLimit = 2000;
static const NSUInteger ScanExtensionLimit = 4096;
static const NSUInteger ScanExtensionLength = 12;
static const NSUInteger ScanBreakdownLimit = 5000;
// A folder tree keeps, per directory, at most this many children at least
// `treeMinimumBytes` large, largest first; the rest are summed into one
// "smaller items" figure. Pruning happens as each directory finishes, so a
// disk with millions of files still publishes a tree of a few thousand nodes.
static const NSUInteger ScanTreeChildLimit = 200;
static const NSUInteger ScanTreeDepthLimit = 64;
// Subdirectories this shallow are measured concurrently. Directory metadata
// calls block in the kernel, so several in flight keep the storage busy;
// deeper levels run on the thread that reached them, which bounds threads.
static const NSUInteger ScanParallelDepth = 4;

// getattrlistbulk packs fields on four-byte boundaries, including 64-bit sizes.
#pragma pack(push, 4)
typedef struct {
	uint32_t length;
	attribute_set_t returned;
	uint32_t error;
	attrreference_t name;
	fsobj_type_t type;
	struct timespec modified;
	struct timespec accessed;
	uint32_t flags;
	uint64_t inode;
	off_t logical;
	off_t allocated;
} ScanEntry;
#pragma pack(pop)

typedef struct { uint64_t inode; dev_t device; } ScanIdentity;
@interface StorageScanJob : NSObject {
	ScanIdentity *_seen;
	NSUInteger _seenCount, _seenCapacity;
	// Guards the identity table, counters, issues and summaries, which
	// concurrent directory walks share.
	os_unfair_lock _lock;
}
@property(atomic) BOOL cancelled;
@property NSArray<NSString *> *roots;
@property NSSet<NSString *> *exclusions;
@property NSMutableArray *trees;
@property NSMutableArray *states;
@property NSMutableArray *issues;
@property NSUInteger errors, protectedErrors, visited, bulkCalls;
@property(atomic) NSTimeInterval started;
@property(atomic, copy) NSString *currentRoot;
@property NSString *failure;
@property NSDictionary *snapshot;
@property BOOL done;
@property NSDictionary<NSString *, NSString *> *logicalRoots;
@property uint64_t capacityBytes, availableBytes;
// Optional summaries requested through `start(roots, exclusions, options)`.
@property NSUInteger fileLimit;
@property uint64_t minimumFileBytes;
@property NSTimeInterval oldBefore;
@property BOOL collectsExtensions, collectsBreakdown;
@property NSMutableArray<NSDictionary *> *largeFiles, *oldFiles;
@property NSMutableDictionary<NSString *, NSMutableArray *> *extensions;
@property NSMutableArray *breakdowns;
@property NSMutableArray *currentBreakdown;
@property NSUInteger treeDepth;
@property uint64_t treeMinimumBytes;
@property NSMutableArray *folderTrees;
@property uint64_t oldBytes, oldCount;
// Per root: logical size of counted files (sparse files and disk images are
// smaller on disk), and files iCloud evicted, which use no local space.
@property uint64_t rootLogical, rootCloudBytes, rootCloudCount;
- (void)run;
- (void)publish:(BOOL)done;
@end
@implementation StorageScanJob
- (instancetype)init {
	if ((self = [super init])) {
		_trees = [NSMutableArray array]; _states = [NSMutableArray array]; _issues = [NSMutableArray array];
		_failure = @"";
		_largeFiles = [NSMutableArray array]; _oldFiles = [NSMutableArray array];
		_extensions = [NSMutableDictionary dictionary]; _breakdowns = [NSMutableArray array];
		_folderTrees = [NSMutableArray array];
	}
	return self;
}
- (void)dealloc {
	free(_seen);
}
static NSUInteger identityHash(ScanIdentity key) {
	uint64_t x = key.inode ^ ((uint64_t)(uint32_t)key.device << 32);
	x = (x ^ (x >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
	x = (x ^ (x >> 27)) * UINT64_C(0x94d049bb133111eb);
	return x ^ (x >> 31);
}
- (BOOL)seenInode:(uint64_t)inode device:(dev_t)device {
	os_unfair_lock_lock(&_lock);
	BOOL seen = [self seenInodeLocked:inode device:device];
	os_unfair_lock_unlock(&_lock);
	return seen;
}
- (void)countLogical:(uint64_t)bytes { os_unfair_lock_lock(&_lock); self.rootLogical += bytes; os_unfair_lock_unlock(&_lock); }
- (void)countCloud:(uint64_t)bytes files:(uint64_t)files {
	os_unfair_lock_lock(&_lock); self.rootCloudBytes += bytes; self.rootCloudCount += files; os_unfair_lock_unlock(&_lock);
}
- (void)countVisited { os_unfair_lock_lock(&_lock); self.visited++; os_unfair_lock_unlock(&_lock); }
- (NSUInteger)liveVisited { os_unfair_lock_lock(&_lock); NSUInteger count = _visited; os_unfair_lock_unlock(&_lock); return count; }
- (NSDictionary *)liveSnapshot:(NSDictionary *)published {
	NSMutableDictionary *snapshot = [published mutableCopy] ?: [NSMutableDictionary dictionary];
	snapshot[@"completed"] = published[@"completed"] ?: @0;
	snapshot[@"total"] = @(self.roots.count);
	snapshot[@"currentPath"] = self.currentRoot ?: @"";
	NSTimeInterval started = self.started;
	snapshot[@"seconds"] = @(started > 0 ? MAX(0, NSProcessInfo.processInfo.systemUptime - started) : 0);
	os_unfair_lock_lock(&_lock);
	snapshot[@"visited"] = @(_visited);
	snapshot[@"errors"] = @(_errors);
	snapshot[@"protected"] = @(_protectedErrors);
	if (self.fileLimit) {
		snapshot[@"largeFiles"] = self.largeFiles.copy;
		snapshot[@"oldFiles"] = self.oldFiles.copy;
	}
	if (self.collectsExtensions) {
		NSMutableArray *extensions = [NSMutableArray arrayWithCapacity:self.extensions.count];
		[self.extensions enumerateKeysAndObjectsUsingBlock:^(NSString *extension, NSMutableArray *totals, BOOL *stop) {
			[extensions addObject:@{@"extension": extension, @"bytes": totals[0], @"count": totals[1], @"oldBytes": totals[2]}];
		}];
		snapshot[@"extensions"] = extensions;
	}
	if (self.oldBefore > 0) { snapshot[@"oldBytes"] = @(_oldBytes); snapshot[@"oldCount"] = @(_oldCount); }
	os_unfair_lock_unlock(&_lock);
	snapshot[@"partial"] = @YES;
	return snapshot;
}
- (BOOL)seenInodeLocked:(uint64_t)inode device:(dev_t)device {
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
// Two refusals no permission can lift are reported apart from privacy
// refusals, which Full Disk Access can: a System Integrity Protection folder
// (the `restricted` flag, as in /System/Library/AssetsV2) refuses every
// process with EPERM, root included, and a folder a system account owns
// refuses others with EACCES. The folder itself still answers lstat. Known
// ones are listed in apps/diskmap/knowledge/Filesystem.lua and never walked.
- (void)issue:(NSString *)path code:(int)code {
	struct stat st;
	BOOL restricted = code == EACCES || (code == EPERM && !lstat(path.fileSystemRepresentation, &st) && (st.st_flags & SF_RESTRICTED));
	os_unfair_lock_lock(&_lock);
	self.errors++;
	if (restricted) self.protectedErrors++;
	if (self.issues.count < ScanIssueLimit) [self.issues addObject:@{@"path": path, @"reason": @(strerror(code)), @"protected": @(restricted)}];
	os_unfair_lock_unlock(&_lock);
}
// Keeps `files` sorted largest first and at most `fileLimit` long.
- (void)rank:(NSDictionary *)file bytes:(uint64_t)bytes into:(NSMutableArray *)files {
	if (files.count >= self.fileLimit && bytes <= [files.lastObject[@"bytes"] unsignedLongLongValue]) return;
	NSUInteger index = [files indexOfObject:file inSortedRange:NSMakeRange(0, files.count)
		options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			return [b[@"bytes"] compare:a[@"bytes"]];
		}];
	[files insertObject:file atIndex:index];
	if (files.count > self.fileLimit) [files removeLastObject];
}
// Records one counted regular file in the optional summaries. A file's last
// use is the later of modification and access, so a file read yesterday is
// never reported as old.
- (void)summarize:(NSString *)path name:(const char *)name bytes:(uint64_t)bytes modified:(struct timespec)modified accessed:(struct timespec)accessed {
	os_unfair_lock_lock(&_lock);
	[self summarizeLocked:path name:name bytes:bytes modified:modified accessed:accessed];
	os_unfair_lock_unlock(&_lock);
}
- (void)summarizeLocked:(NSString *)path name:(const char *)name bytes:(uint64_t)bytes modified:(struct timespec)modified accessed:(struct timespec)accessed {
	NSTimeInterval changed = modified.tv_sec + modified.tv_nsec / 1e9;
	NSTimeInterval used = MAX(changed, accessed.tv_sec + accessed.tv_nsec / 1e9);
	BOOL old = self.oldBefore > 0 && used > 0 && used < self.oldBefore;
	if (old) { self.oldBytes += bytes; self.oldCount++; }
	if (self.collectsExtensions) {
		const char *dot = strrchr(name, '.');
		NSString *extension = @"";
		if (dot && dot != name && dot[1] && strlen(dot + 1) <= ScanExtensionLength)
			extension = [[NSString alloc] initWithUTF8String:dot + 1].lowercaseString ?: @"";
		if (!self.extensions[extension] && self.extensions.count >= ScanExtensionLimit) extension = @"";
		NSMutableArray *totals = self.extensions[extension];
		if (!totals) { totals = [NSMutableArray arrayWithObjects:@0, @0, @0, nil]; self.extensions[extension] = totals; }
		totals[0] = @([totals[0] unsignedLongLongValue] + bytes);
		totals[1] = @([totals[1] unsignedLongLongValue] + 1);
		if (old) totals[2] = @([totals[2] unsignedLongLongValue] + bytes);
	}
	if (self.fileLimit == 0 || bytes < self.minimumFileBytes) return;
	NSDictionary *file = @{@"path": path, @"bytes": @(bytes), @"modified": @(changed), @"used": @(used)};
	[self rank:file bytes:bytes into:self.largeFiles];
	if (old) [self rank:file bytes:bytes into:self.oldFiles];
}
- (BOOL)stopped {
	if (self.cancelled || self.failure.length) return YES;
	if (NSProcessInfo.processInfo.systemUptime - self.started > ScanTimeout) {
		self.failure = @"Scan exceeded ten minutes."; return YES;
	}
	return NO;
}
// Scans read metadata only: never let the file system download an evicted
// iCloud file or folder to answer them. The policy is per thread, so every
// thread that walks directories sets it.
static void scanNeverMaterialize(void) {
	setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF);
}
static NSTimeInterval lastUse(struct timespec modified, struct timespec accessed) {
	return MAX(modified.tv_sec + modified.tv_nsec / 1e9, accessed.tv_sec + accessed.tv_nsec / 1e9);
}
// `node`, when the scan collects a folder tree and this directory is within
// its depth, receives this directory's largest children (`children`), the
// rest as `otherKb`/`otherCount`, and `used`, the latest use of anything
// inside. `latest` always receives that latest use for the caller's node.
- (uint64_t)directory:(int)fd path:(NSString *)path device:(dev_t)device depth:(NSUInteger)depth
	node:(NSMutableDictionary *)node latest:(NSTimeInterval *)latest {
	if ([self stopped]) return 0;
	if (depth > ScanDepthLimit) { [self issue:path code:ELOOP]; return 0; }
	struct stat st;
	if (fstat(fd, &st)) { [self issue:path code:errno]; return 0; }
	if (st.st_dev != device) return 0;
	[self countVisited];
	if ([self seenInode:st.st_ino device:device]) return 0;
	uint64_t bytes = (uint64_t)st.st_blocks * 512;
	NSTimeInterval newest = 0;
	NSMutableArray<NSDictionary *> *entries = node ? [NSMutableArray array] : nil;
	uint64_t smallBytes = 0, smallCount = 0;
	void *buffer = malloc(ScanBufferSize);
	NSMutableArray<NSString *> *childNames = [NSMutableArray array], *childPaths = [NSMutableArray array];
	if (!buffer) { self.failure = @"Not enough memory for directory metadata."; return bytes; }
	struct attrlist attrs = {.bitmapcount = ATTR_BIT_MAP_COUNT,
		.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_ERROR | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_ACCTIME | ATTR_CMN_FLAGS | ATTR_CMN_FILEID,
		.fileattr = ATTR_FILE_TOTALSIZE | ATTR_FILE_ALLOCSIZE};
	while (![self stopped]) {
		int count = getattrlistbulk(fd, &attrs, buffer, ScanBufferSize, FSOPT_PACK_INVAL_ATTRS);
		os_unfair_lock_lock(&_lock); self.bulkCalls++; os_unfair_lock_unlock(&_lock);
		if (count <= 0) { if (count < 0) [self issue:path code:errno]; break; }
		char *cursor = buffer, *end = cursor + ScanBufferSize;
		for (int i = 0; i < count && ![self stopped]; i++) { @autoreleasepool {
			if (end - cursor < offsetof(ScanEntry, logical)) { [self issue:path code:EIO]; break; }
			ScanEntry entry = {0}; memcpy(&entry, cursor, offsetof(ScanEntry, logical));
			NSUInteger fixedSize = entry.type == VREG ? sizeof(entry) : offsetof(ScanEntry, logical);
			if (entry.length < fixedSize || entry.length > end - cursor) { [self issue:path code:EIO]; break; }
			int64_t nameOffset = offsetof(ScanEntry, name) + (int64_t)entry.name.attr_dataoffset;
			if (!(entry.returned.commonattr & ATTR_CMN_NAME) || nameOffset < fixedSize ||
				entry.name.attr_length < 1 || nameOffset + entry.name.attr_length > entry.length) { [self issue:path code:EIO]; cursor += entry.length; continue; }
			if (entry.type == VREG) memcpy(&entry.logical, cursor + offsetof(ScanEntry, logical), sizeof(entry.logical) + sizeof(entry.allocated));
			const char *name = cursor + nameOffset;
			if (name[entry.name.attr_length - 1] != '\0' || strchr(name, '/')) { [self issue:path code:EIO]; cursor += entry.length; continue; }
			NSString *component = [[NSString alloc] initWithBytes:name length:strlen(name) encoding:NSUTF8StringEncoding];
			NSString *child = [path stringByAppendingPathComponent:component ?: @"<invalid filename>"];
			cursor += entry.length;
			if (!strcmp(name, ".") || !strcmp(name, "..") || [self.exclusions containsObject:child]) continue;
			if (entry.error) { [self issue:child code:entry.error]; continue; }
			if (!(entry.returned.commonattr & ATTR_CMN_OBJTYPE)) { [self issue:child code:ENOTSUP]; continue; }
			BOOL dataless = (entry.returned.commonattr & ATTR_CMN_FLAGS) && (entry.flags & SF_DATALESS);
			if (entry.type == VDIR && dataless) {
				// An evicted iCloud folder: entering it would download it.
				[self countCloud:0 files:0];
				continue;
			}
			if (entry.type == VDIR) {
				// Subdirectories are walked after this directory's entries,
				// concurrently when shallow.
				[childNames addObject:component ?: @""];
				[childPaths addObject:child];
			} else if (entry.type == VREG) {
				uint64_t inode = entry.inode; off_t allocated = entry.allocated, logical = entry.logical;
				struct timespec modified = entry.modified, accessed = entry.accessed;
				if (!(entry.returned.commonattr & ATTR_CMN_FILEID) || !(entry.returned.fileattr & ATTR_FILE_ALLOCSIZE)) {
					struct stat fileStat;
					if (fstatat(fd, name, &fileStat, AT_SYMLINK_NOFOLLOW)) { [self issue:child code:errno]; continue; }
					if (!S_ISREG(fileStat.st_mode) || fileStat.st_dev != device) continue;
					inode = fileStat.st_ino; allocated = fileStat.st_blocks * 512; logical = fileStat.st_size;
					dataless = (fileStat.st_flags & SF_DATALESS) != 0;
					modified = fileStat.st_mtimespec; accessed = fileStat.st_atimespec;
				}
				[self countVisited];
				if (allocated < 0) { [self issue:child code:EIO]; continue; }
				BOOL alreadyCounted = [self seenInode:inode device:device];
				uint64_t fileBytes = (uint64_t)allocated;
				if (!alreadyCounted) {
					bytes += fileBytes;
					if (dataless) [self countCloud:(uint64_t)MAX(0, logical) files:1];
					else [self countLogical:(uint64_t)MAX(0, logical)];
					[self summarize:child name:name bytes:fileBytes modified:modified accessed:accessed];
				}
				if (depth == 0) [self breakdown:component bytes:alreadyCounted ? 0 : fileBytes directory:NO];
				if (!alreadyCounted) {
					NSTimeInterval used = lastUse(modified, accessed);
					newest = MAX(newest, used);
					// Small files never become nodes; only their total is kept.
					if (entries && fileBytes > 0 && fileBytes < self.treeMinimumBytes) { smallBytes += fileBytes; smallCount++; }
					else if (entries && component) [entries addObject:@{@"name": component, @"kb": @(fileBytes / 1024.0), @"used": @(used), @"bytes": @(fileBytes)}];
				}
			}
		} }
	}
	free(buffer);
	NSUInteger count = childPaths.count;
	uint64_t *sizes = calloc(count ?: 1, sizeof(uint64_t));
	NSTimeInterval *uses = calloc(count ?: 1, sizeof(NSTimeInterval));
	// Each child's node is created here and filled only by the thread that
	// walks that child, so concurrent walks never share a mutable object.
	NSMutableArray<NSMutableDictionary *> *childNodes = nil;
	if (node && depth + 1 < self.treeDepth) {
		childNodes = [NSMutableArray arrayWithCapacity:count];
		for (NSUInteger index = 0; index < count; index++) [childNodes addObject:[NSMutableDictionary dictionary]];
	}
	void (^walk)(size_t) = ^(size_t index) { @autoreleasepool {
		if ([self stopped]) return;
		scanNeverMaterialize();
		NSString *child = childPaths[index];
		int childFD = openat(fd, childNames[index].fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
		if (childFD < 0) { [self issue:child code:errno]; return; }
		sizes[index] = [self directory:childFD path:child device:device depth:depth + 1
			node:childNodes[index] latest:&uses[index]];
		close(childFD);
	} };
	if (count > 1 && depth < ScanParallelDepth) {
		dispatch_apply(count, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), walk);
	} else {
		for (NSUInteger index = 0; index < count; index++) walk(index);
	}
	for (NSUInteger index = 0; index < count; index++) {
		bytes += sizes[index];
		newest = MAX(newest, uses[index]);
		if (depth == 0) [self breakdown:childNames[index] bytes:sizes[index] directory:YES];
		if (entries) {
			NSMutableDictionary *child = childNodes ? childNodes[index] : [NSMutableDictionary dictionary];
			child[@"name"] = childNames[index]; child[@"kb"] = @(sizes[index] / 1024.0);
			child[@"bytes"] = @(sizes[index]); child[@"used"] = @(uses[index]); child[@"directory"] = @YES;
			// A directory below the tree's depth has no `children`: its
			// contents are measured but not listed.
			if (!childNodes) child[@"deeper"] = @YES;
			[entries addObject:child];
		}
	}
	free(sizes); free(uses);
	if (entries) [self prune:entries into:node smallBytes:smallBytes smallCount:smallCount];
	if (latest) *latest = newest;
	return bytes;
}
// Keeps the largest children at least `treeMinimumBytes` large and folds
// the rest into the node's "smaller items".
- (void)prune:(NSMutableArray<NSDictionary *> *)entries into:(NSMutableDictionary *)node
	smallBytes:(uint64_t)smallBytes smallCount:(uint64_t)smallCount {
	[entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"bytes"] compare:a[@"bytes"]]; }];
	NSMutableArray *kept = [NSMutableArray array];
	uint64_t otherBytes = smallBytes, otherCount = smallCount;
	for (NSDictionary *entry in entries) {
		uint64_t size = [entry[@"bytes"] unsignedLongLongValue];
		if (size == 0) continue;
		if (kept.count < ScanTreeChildLimit && size >= self.treeMinimumBytes) {
			NSMutableDictionary *copy = [entry mutableCopy];
			[copy removeObjectForKey:@"bytes"];
			[kept addObject:copy];
		} else { otherBytes += size; otherCount++; }
	}
	node[@"children"] = kept;
	if (otherCount) { node[@"otherKb"] = @(otherBytes / 1024.0); node[@"otherCount"] = @(otherCount); }
}
// Immediate children of a scanned root, so a category can be opened one level
// deeper without a second scan.
- (void)breakdown:(NSString *)name bytes:(uint64_t)bytes directory:(BOOL)directory {
	if (!self.currentBreakdown || self.currentBreakdown.count >= ScanBreakdownLimit || !name) return;
	[self.currentBreakdown addObject:@{@"name": name, @"kb": @(bytes / 1024.0), @"directory": @(directory)}];
}
// The space a volume uses, when `path` is where it is mounted; 0 otherwise.
// APFS reports a clone's blocks under every file that shares them, so the
// files of a volume of clones (Preboot's cryptexes and staged updates) add
// up to several times what the volume holds. The volume's own figure is the
// one Disk Utility shows.
static uint64_t volumeUsedBytes(NSString *path) {
	struct statfs fs;
	if (statfs(path.fileSystemRepresentation, &fs) || strcmp(fs.f_mntonname, path.fileSystemRepresentation)) return 0;
	struct attrlist request = {.bitmapcount = ATTR_BIT_MAP_COUNT, .volattr = ATTR_VOL_INFO | ATTR_VOL_SPACEUSED};
	struct { uint32_t length; off_t used; } __attribute__((aligned(4), packed)) reply;
	if (getattrlist(path.fileSystemRepresentation, &request, &reply, sizeof reply, 0) || reply.used <= 0) return 0;
	return (uint64_t)reply.used;
}
- (void)root:(NSString *)path {
	NSString *state = nil; NSDictionary *tree = nil, *rootFolder = nil;
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
			self.currentBreakdown = self.collectsBreakdown ? [NSMutableArray array] : nil;
			self.rootLogical = self.rootCloudBytes = self.rootCloudCount = 0;
			NSMutableDictionary *folder = self.treeDepth ? [NSMutableDictionary dictionary] : nil;
			NSTimeInterval used = 0;
			if (fd < 0) [self issue:path code:errno];
			else { bytes = [self directory:fd path:logicalPath device:st.st_dev depth:0 node:folder latest:&used]; close(fd); }
			// A whole volume never measures more than it uses: what its files
			// claim beyond that is shared between clones, reported as
			// `sharedKb`, and the children give it up in proportion so they
			// still add up to their root.
			uint64_t volume = fd < 0 ? 0 : volumeUsedBytes(path), shared = 0;
			if (volume && bytes > volume) {
				shared = bytes - volume;
				double scale = (double)volume / (double)bytes;
				for (NSUInteger index = 0; index < self.currentBreakdown.count; index++) {
					NSMutableDictionary *child = [self.currentBreakdown[index] mutableCopy];
					child[@"kb"] = @([child[@"kb"] doubleValue] * scale);
					self.currentBreakdown[index] = child;
				}
				bytes = volume;
			}
			if (folder) {
				folder[@"name"] = logicalPath.lastPathComponent; folder[@"kb"] = @(bytes / 1024.0);
				folder[@"used"] = @(used); folder[@"directory"] = @YES;
				if (!folder[@"children"]) folder[@"children"] = @[];
				rootFolder = folder;
			}
			tree = @{@"kb": @(bytes / 1024.0), @"partial": self.errors > before ? @YES : @NO, @"logicalKb": @(self.rootLogical / 1024.0),
				@"cloudKb": @(self.rootCloudBytes / 1024.0), @"cloudFiles": @(self.rootCloudCount),
				@"volumeKb": @(volume / 1024.0), @"sharedKb": @(shared / 1024.0)};
		} else if (S_ISREG(st.st_mode)) {
			[self countVisited];
			BOOL alreadyCounted = [self seenInode:st.st_ino device:st.st_dev];
			uint64_t fileBytes = (uint64_t)st.st_blocks * 512;
			NSString *logicalPath = self.logicalRoots[path] ?: path;
			if (!alreadyCounted) [self summarize:logicalPath name:name bytes:fileBytes modified:st.st_mtimespec accessed:st.st_atimespec];
			BOOL evicted = (st.st_flags & SF_DATALESS) != 0 && !alreadyCounted;
			if (self.treeDepth) rootFolder = @{@"name": logicalPath.lastPathComponent, @"kb": @(alreadyCounted ? 0 : fileBytes / 1024.0),
				@"used": @(lastUse(st.st_mtimespec, st.st_atimespec)), @"directory": @NO};
			tree = @{@"kb": @(alreadyCounted ? 0 : fileBytes / 1024.0), @"logicalKb": @(alreadyCounted || evicted ? 0 : st.st_size / 1024.0),
				@"cloudKb": @(evicted ? st.st_size / 1024.0 : 0), @"cloudFiles": @(evicted ? 1 : 0)};
		} else state = @"skipped";
		close(parent);
	} else if (!state) { state = @"unreadable"; [self issue:path code:errno]; }
	// A cancelled or timed-out root never becomes a complete measurement.
	if ([self stopped]) return;
	if (self.collectsBreakdown) [self.breakdowns addObject:self.currentBreakdown ?: @[]];
	self.currentBreakdown = nil;
	if (self.treeDepth) [self.folderTrees addObject:rootFolder ?: NSNull.null];
	[self.trees addObject:tree ?: NSNull.null];
	[self.states addObject:state ?: (self.errors > before ? @"unreadable" : @"measured")];
}
- (void)publish:(BOOL)done {
	NSDictionary *snapshot = @{@"trees": self.trees.copy, @"rootStates": self.states.copy,
		@"completed": @(self.states.count), @"total": @(self.roots.count), @"issues": self.issues.copy,
		@"errors": @(self.errors), @"protected": @(self.protectedErrors), @"visited": @(self.visited), @"bulkCalls": @(self.bulkCalls),
		@"seconds": @(NSProcessInfo.processInfo.systemUptime - self.started),
		@"failure": self.cancelled ? @"Measurement cancelled." : self.failure,
		@"partial": (self.errors > 0 || self.failure.length > 0 || self.cancelled) ? @YES : @NO};
	// Final summaries belong to the completed batch. Pending polls copy live
	// rankings under the worker lock without publishing unfinished root trees.
	if (done && (self.fileLimit || self.collectsExtensions || self.collectsBreakdown || self.treeDepth || self.oldBefore > 0)) {
		NSMutableDictionary *complete = [snapshot mutableCopy];
		if (self.fileLimit) { complete[@"largeFiles"] = self.largeFiles.copy; complete[@"oldFiles"] = self.oldFiles.copy; }
		if (self.collectsExtensions) {
			NSMutableArray *rows = [NSMutableArray arrayWithCapacity:self.extensions.count];
			[self.extensions enumerateKeysAndObjectsUsingBlock:^(NSString *extension, NSMutableArray *totals, BOOL *stop) {
				[rows addObject:@{@"extension": extension, @"bytes": totals[0], @"count": totals[1], @"oldBytes": totals[2]}];
			}];
			complete[@"extensions"] = rows;
		}
		if (self.collectsBreakdown) complete[@"breakdowns"] = self.breakdowns.copy;
		if (self.treeDepth) complete[@"folders"] = self.folderTrees.copy;
		if (self.oldBefore > 0) { complete[@"oldBytes"] = @(self.oldBytes); complete[@"oldCount"] = @(self.oldCount); }
		snapshot = complete;
	}
	@synchronized(self) { self.snapshot = snapshot; self.done = done; }
}
- (void)run {
	@autoreleasepool {
		self.started = NSProcessInfo.processInfo.systemUptime;
		scanNeverMaterialize();
		@try {
			for (NSString *path in self.roots) {
				if ([self stopped]) break;
				self.currentRoot = path;
				@autoreleasepool { [self root:path]; [self publish:NO]; }
			}
		} @catch (NSException *exception) { self.failure = exception.reason ?: @"Native scan failed."; }
		self.currentRoot = nil;
		[self publish:YES];
		free(_seen); _seen = NULL; _seenCount = 0; _seenCapacity = 0;
	}
}
@end

// Results keep their types across the bridge. Strings carry their byte
// length, so output with embedded NULs (`mdls -raw` separates values with
// them) arrives whole. Counts arrive as Lua integers and print without ".0".
// Only a CFBoolean is a Lua boolean: a flag boxed from a C expression
// (`@(a > b)`) is an int that Lua would find truthy even when 0, so flags
// are always built from @YES and @NO.
static void pushValue(lua_State *L, id value) {
	if (!value || value == NSNull.null) { lua_pushnil(L); return; }
	if ([value isKindOfClass:NSString.class]) {
		NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
		lua_pushlstring(L, bytes.bytes ?: "", bytes.length);
	} else if ([value isKindOfClass:NSNumber.class]) {
		if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) lua_pushboolean(L, [value boolValue]);
		else if (CFNumberIsFloatType((__bridge CFNumberRef)value)) lua_pushnumber(L, [value doubleValue]);
		else lua_pushinteger(L, [value longLongValue]);
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
			@synchronized(job) { job.result = @{@"ok": (!overflow && job.task.terminationStatus == 0) ? @YES : @NO, @"output": output}; job.done = YES; }
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
	if (lua_istable(L, 3)) {
		lua_getfield(L, 3, "files");
		lua_Integer files = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
		luaL_argcheck(L, files >= 0, 3, "files must be nonnegative");
		job.fileLimit = MIN((NSUInteger)files, ScanFileLimit);
		lua_getfield(L, 3, "minimumFileBytes");
		job.minimumFileBytes = (uint64_t)MAX(0, luaL_optnumber(L, -1, 0)); lua_pop(L, 1);
		lua_getfield(L, 3, "oldBefore");
		job.oldBefore = luaL_optnumber(L, -1, 0); lua_pop(L, 1);
		lua_getfield(L, 3, "extensions");
		job.collectsExtensions = lua_toboolean(L, -1); lua_pop(L, 1);
		lua_getfield(L, 3, "breakdown");
		job.collectsBreakdown = lua_toboolean(L, -1); lua_pop(L, 1);
		lua_getfield(L, 3, "treeDepth");
		lua_Integer treeDepth = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
		luaL_argcheck(L, treeDepth >= 0, 3, "treeDepth must be nonnegative");
		job.treeDepth = MIN((NSUInteger)treeDepth, ScanTreeDepthLimit);
		lua_getfield(L, 3, "treeMinimumBytes");
		job.treeMinimumBytes = (uint64_t)MAX(0, luaL_optnumber(L, -1, 0)); lua_pop(L, 1);
		// `logicalRoots` names a physical root by the path people know, as
		// the startup disk's Data volume is known as "/".
		lua_getfield(L, 3, "logicalRoots");
		if (lua_istable(L, -1)) {
			int mappings = lua_gettop(L);
			NSMutableDictionary *logicalRoots = [NSMutableDictionary dictionary];
			lua_pushnil(L);
			while (lua_next(L, mappings)) {
				luaL_argcheck(L, lua_type(L, -2) == LUA_TSTRING && lua_type(L, -1) == LUA_TSTRING, 3, "logicalRoots maps paths to paths");
				NSString *physical = absolutePathArgument(L, -2, 3);
				NSString *logical = absolutePathArgument(L, -1, 3);
				luaL_argcheck(L, [roots containsObject:physical], 3, "logicalRoots keys must also be scan roots");
				logicalRoots[physical] = logical;
				lua_pop(L, 1);
			}
			job.logicalRoots = logicalRoots.copy;
		}
		lua_pop(L, 1);
	}
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
	if (!done) snapshot = [job liveSnapshot:snapshot];
	lua_pushboolean(L, done); pushValue(L, snapshot); return 2;
}
static int cancel(lua_State *L) { checkJob(L).cancelled = YES; return 0; }
// Lightweight item counter for callers that do not need a full snapshot.
static int progress(lua_State *L) { lua_pushinteger(L, (lua_Integer)[checkJob(L) liveVisited]); return 1; }
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
	const luaL_Reg functions[] = {{"commandStart", commandStart}, {"commandPoll", commandPoll}, {"start", start}, {"poll", poll},
		{"progress", progress}, {"cancel", cancel}, {"scan", scan}, {NULL, NULL}};
	luaL_newlib(L, functions); lua_pushliteral(L, "getattrlistbulk"); lua_setfield(L, -2, "backend");
	return 1;
}
