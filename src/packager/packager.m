#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

static NSString *gRoot;
static NSString *gEntry = @"examples/hello";
static uint16_t gPort = 8081;
static lua_State *gL;
static NSMutableArray<NSNumber *> *gClients;
static dispatch_queue_t gClientQueue;

static NSString *sha1_b64(NSString *src) {
	NSData *data = [src dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
	return [[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH]
		base64EncodedStringWithOptions:0];
}

static NSString *lua_call_string(const char *fn, NSString *arg) {
	lua_getglobal(gL, "packager");
	lua_getfield(gL, -1, fn);
	lua_pushstring(gL, arg.UTF8String);
	if (lua_pcall(gL, 1, 1, 0) != LUA_OK) {
		fprintf(stderr, "packager: %s\n", lua_tostring(gL, -1));
		lua_pop(gL, 2);
		return nil;
	}
	NSString *result = nil;
	if (lua_isstring(gL, -1)) {
		result = @(lua_tostring(gL, -1));
	}
	lua_pop(gL, 2);
	return result;
}

static BOOL lua_watched(NSString *rel) {
	lua_getglobal(gL, "packager");
	lua_getfield(gL, -1, "watched");
	lua_pushstring(gL, rel.UTF8String);
	BOOL ok = lua_pcall(gL, 1, 1, 0) == LUA_OK && lua_toboolean(gL, -1);
	lua_pop(gL, 2);
	return ok;
}

static NSString *jail_full(NSString *rel, NSString **outRel) {
	lua_getglobal(gL, "packager");
	lua_getfield(gL, -1, "jail");
	lua_pushstring(gL, gRoot.UTF8String);
	lua_pushstring(gL, rel.UTF8String);
	if (lua_pcall(gL, 2, 2, 0) != LUA_OK) {
		lua_pop(gL, 2);
		return nil;
	}
	if (!lua_isstring(gL, -2)) {
		lua_pop(gL, 3);
		return nil;
	}
	NSString *full = @(lua_tostring(gL, -2));
	if (outRel && lua_isstring(gL, -1)) *outRel = @(lua_tostring(gL, -1));
	lua_pop(gL, 3);
	return full;
}

static NSData *read_jailed(NSString *rel, NSString **ctype) {
	NSString *norm = nil;
	NSString *full = jail_full(rel, &norm);
	if (!full) return nil;
	NSData *data = [NSData dataWithContentsOfFile:full];
	if (!data) return nil;
	if (ctype) {
		NSString *ct = lua_call_string("contentType", norm ?: rel);
		*ctype = ct ?: @"application/octet-stream";
	}
	return data;
}

static NSString *url_decode(NSString *value) {
	return [value stringByRemovingPercentEncoding] ?: value;
}

static NSString *query_param(NSString *query, NSString *key) {
	if (query.length == 0) return nil;
	for (NSString *part in [query componentsSeparatedByString:@"&"]) {
		NSRange eq = [part rangeOfString:@"="];
		if (eq.location == NSNotFound) continue;
		NSString *k = [part substringToIndex:eq.location];
		if ([k isEqualToString:key]) {
			return url_decode([part substringFromIndex:eq.location + 1]);
		}
	}
	return nil;
}

static void ws_send(int fd, NSString *text) {
	NSData *payload = [text dataUsingEncoding:NSUTF8StringEncoding];
	NSUInteger len = payload.length;
	uint8_t header[10];
	NSUInteger hlen = 2;
	header[0] = 0x81;
	if (len < 126) {
		header[1] = (uint8_t)len;
	} else if (len <= 0xFFFF) {
		header[1] = 126;
		header[2] = (uint8_t)((len >> 8) & 0xFF);
		header[3] = (uint8_t)(len & 0xFF);
		hlen = 4;
	} else {
		return;
	}
	write(fd, header, hlen);
	write(fd, payload.bytes, payload.length);
}

static void broadcast(NSString *json) {
	dispatch_sync(gClientQueue, ^{
		NSMutableArray *dead = [NSMutableArray array];
		for (NSNumber *n in gClients) {
			if (write(n.intValue, "", 0) != 0 && errno == EBADF) {
				[dead addObject:n];
				continue;
			}
			ws_send(n.intValue, json);
		}
		[gClients removeObjectsInArray:dead];
	});
	fprintf(stderr, "ws update %s\n", json.UTF8String);
}

static void http_reply(int fd, int status, NSString *ctype, NSData *body) {
	NSString *reason = status == 200 ? @"OK" : (status == 101 ? @"Switching Protocols" : @"Error");
	NSMutableString *head = [NSMutableString stringWithFormat:
		@"HTTP/1.1 %d %@\r\nContent-Length: %lu\r\nConnection: close\r\n",
		status, reason, (unsigned long)body.length];
	if (ctype) [head appendFormat:@"Content-Type: %@\r\n", ctype];
	[head appendString:@"\r\n"];
	NSData *h = [head dataUsingEncoding:NSUTF8StringEncoding];
	write(fd, h.bytes, h.length);
	if (body.length) write(fd, body.bytes, body.length);
}

static NSString *json_escape(NSString *s) {
	return [[[[[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]
		stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]
		stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"]
		stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
}

static void handle_get(int fd, NSString *path, NSString *query, NSDictionary *headers) {
	if ([path isEqualToString:@"/health"]) {
		NSString *body = [NSString stringWithFormat:
			@"{\"status\":\"ok\",\"root\":\"%@\"}", json_escape(gRoot)];
		http_reply(fd, 200, @"application/json",
			[body dataUsingEncoding:NSUTF8StringEncoding]);
		return;
	}
	if ([path isEqualToString:@"/entry"]) {
		NSString *entry = gEntry;
		if (![entry hasSuffix:@".lua"]) {
			entry = [entry stringByAppendingPathComponent:@"init.lua"];
		}
		NSString *body = [NSString stringWithFormat:@"{\"path\":\"%@\"}",
			json_escape(entry)];
		http_reply(fd, 200, @"application/json",
			[body dataUsingEncoding:NSUTF8StringEncoding]);
		return;
	}
	if ([path isEqualToString:@"/file"]) {
		NSString *rel = query_param(query, @"path");
		NSString *ctype = nil;
		NSData *data = rel ? read_jailed(rel, &ctype) : nil;
		if (!data) {
			http_reply(fd, 404, @"text/plain",
				[@"not found" dataUsingEncoding:NSUTF8StringEncoding]);
			return;
		}
		http_reply(fd, 200, ctype, data);
		return;
	}
	if ([path isEqualToString:@"/module"]) {
		NSString *name = query_param(query, @"name");
		if (!name) {
			http_reply(fd, 400, @"text/plain",
				[@"missing name" dataUsingEncoding:NSUTF8StringEncoding]);
			return;
		}
		lua_getglobal(gL, "packager");
		lua_getfield(gL, -1, "moduleCandidates");
		lua_pushstring(gL, name.UTF8String);
		if (lua_pcall(gL, 1, 2, 0) != LUA_OK) {
			lua_pop(gL, 2);
			http_reply(fd, 404, @"text/plain",
				[@"error" dataUsingEncoding:NSUTF8StringEncoding]);
			return;
		}
		/* stack: packager, candidates|nil, err */
		if (!lua_istable(gL, -2)) {
			lua_pop(gL, 3);
			http_reply(fd, 404, @"text/plain",
				[@"native" dataUsingEncoding:NSUTF8StringEncoding]);
			return;
		}
		lua_pop(gL, 1); /* err */
		NSData *found = nil;
		NSString *ctype = @"text/plain; charset=utf-8";
		lua_pushnil(gL);
		while (lua_next(gL, -2)) {
			if (lua_isstring(gL, -1) && !found) {
				NSString *rel = @(lua_tostring(gL, -1));
				found = read_jailed(rel, &ctype);
			}
			lua_pop(gL, 1);
		}
		lua_pop(gL, 2); /* candidates, packager */
		if (!found) {
			http_reply(fd, 404, @"text/plain",
				[@"not found" dataUsingEncoding:NSUTF8StringEncoding]);
			return;
		}
		http_reply(fd, 200, ctype, found);
		return;
	}
	if ([path isEqualToString:@"/hot"]) {
		NSString *key = headers[@"Sec-WebSocket-Key"];
		if (key.length == 0) {
			http_reply(fd, 400, @"text/plain",
				[@"expected websocket" dataUsingEncoding:NSUTF8StringEncoding]);
			return;
		}
		NSString *accept = sha1_b64([key stringByAppendingString:
			@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"]);
		NSString *head = [NSString stringWithFormat:
			@"HTTP/1.1 101 Switching Protocols\r\n"
			@"Upgrade: websocket\r\nConnection: Upgrade\r\n"
			@"Sec-WebSocket-Accept: %@\r\n\r\n", accept];
		NSData *h = [head dataUsingEncoding:NSUTF8StringEncoding];
		write(fd, h.bytes, h.length);
		ws_send(fd, @"{\"type\":\"hello\",\"protocol\":1}");
		dispatch_sync(gClientQueue, ^{ [gClients addObject:@(fd)]; });
		fprintf(stderr, "ws client fd=%d\n", fd);
		return;
	}
	http_reply(fd, 404, @"text/plain",
		[@"not found" dataUsingEncoding:NSUTF8StringEncoding]);
}

static NSDictionary *parse_headers(NSString *block) {
	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	NSArray *lines = [block componentsSeparatedByString:@"\r\n"];
	for (NSUInteger i = 1; i < lines.count; i++) {
		NSString *line = lines[i];
		NSRange c = [line rangeOfString:@":"];
		if (c.location == NSNotFound) continue;
		NSString *k = [line substringToIndex:c.location];
		NSString *v = [[line substringFromIndex:c.location + 1]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		headers[k] = v;
	}
	return headers;
}

static void serve_client(int fd) {
	char buf[8192];
	ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
	if (n <= 0) { close(fd); return; }
	buf[n] = 0;
	NSString *req = @(buf);
	NSRange sep = [req rangeOfString:@"\r\n\r\n"];
	if (sep.location == NSNotFound) { close(fd); return; }
	NSString *head = [req substringToIndex:sep.location];
	NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
	NSArray *reqline = [lines.firstObject componentsSeparatedByString:@" "];
	if (reqline.count < 2) { close(fd); return; }
	NSURL *url = [NSURL URLWithString:reqline[1] relativeToURL:
		[NSURL URLWithString:@"http://127.0.0.1/"]];
	NSString *path = url.path ?: @"/";
	NSString *query = url.query ?: @"";
	NSDictionary *headers = parse_headers(head);
	BOOL keep = [path isEqualToString:@"/hot"]
		&& headers[@"Sec-WebSocket-Key"] != nil;
	fprintf(stderr, "get %s%s%s\n", path.UTF8String,
		query.length ? "?" : "", query.UTF8String ?: "");
	handle_get(fd, path, query, headers);
	if (!keep) close(fd);
}

static void on_fs_event(
	ConstFSEventStreamRef stream,
	void *info,
	size_t count,
	void *paths,
	const FSEventStreamEventFlags *flags,
	const FSEventStreamEventId *ids
) {
	(void)stream; (void)info; (void)flags; (void)ids;
	char **p = paths;
	for (size_t i = 0; i < count; i++) {
		NSString *full = @(p[i]);
		if (![full hasPrefix:gRoot]) continue;
		NSString *rel = [full substringFromIndex:gRoot.length];
		if ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
		fprintf(stderr, "watch %s\n", rel.UTF8String);
		NSString *norm = nil;
		if (!jail_full(rel, &norm)) continue;
		if (!lua_watched(norm ?: rel)) continue;
		NSString *kind = lua_call_string("kind", norm ?: rel) ?: @"runtime";
		NSString *json = [NSString stringWithFormat:
			@"{\"type\":\"update\",\"path\":\"%@\",\"kind\":\"%@\"}",
			json_escape(norm ?: rel), json_escape(kind)];
		broadcast(json);
	}
}

int main(int argc, char **argv) {
	@autoreleasepool {
		gRoot = [[[NSFileManager defaultManager] currentDirectoryPath]
			stringByStandardizingPath];
		for (int i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--root") == 0 && i + 1 < argc) {
				gRoot = [@(argv[++i]) stringByStandardizingPath];
			} else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
				gPort = (uint16_t)atoi(argv[++i]);
			} else if (strcmp(argv[i], "--entry") == 0 && i + 1 < argc) {
				gEntry = @(argv[++i]);
			}
		}
		if (![gRoot hasPrefix:@"/"]) {
			gRoot = [[[NSFileManager defaultManager] currentDirectoryPath]
				stringByAppendingPathComponent:gRoot];
			gRoot = [gRoot stringByStandardizingPath];
		}

		gL = luaL_newstate();
		luaL_openlibs(gL);
		NSString *pathsLua = [gRoot stringByAppendingPathComponent:
			@"lua/packager/paths.lua"];
		if (luaL_dofile(gL, pathsLua.UTF8String) != LUA_OK) {
			fprintf(stderr, "packager: %s\n", lua_tostring(gL, -1));
			return 1;
		}
		lua_setglobal(gL, "packager");

		gClients = [NSMutableArray array];
		gClientQueue = dispatch_queue_create("lua-objc.packager.ws",
			DISPATCH_QUEUE_SERIAL);

		int srv = socket(AF_INET, SOCK_STREAM, 0);
		int yes = 1;
		setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
		struct sockaddr_in addr = {0};
		addr.sin_family = AF_INET;
		addr.sin_port = htons(gPort);
		addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
			perror("bind");
			return 1;
		}
		listen(srv, 16);

		FSEventStreamContext ctx = {0};
		CFStringRef path = (__bridge CFStringRef)gRoot;
		CFArrayRef paths = CFArrayCreate(NULL, (const void **)&path, 1, &kCFTypeArrayCallBacks);
		FSEventStreamRef stream = FSEventStreamCreate(
			NULL, on_fs_event, &ctx, paths,
			kFSEventStreamEventIdSinceNow, 0.2,
			kFSEventStreamCreateFlagFileEvents);
		CFRelease(paths);
		FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(),
			kCFRunLoopDefaultMode);
		FSEventStreamStart(stream);

		fprintf(stderr, "lua-objc-packager http://127.0.0.1:%u  entry=%s\n",
			gPort, gEntry.UTF8String);

		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			for (;;) {
				int fd = accept(srv, NULL, NULL);
				if (fd < 0) continue;
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
					serve_client(fd);
				});
			}
		});

		[[NSRunLoop mainRunLoop] run];
	}
	return 0;
}
