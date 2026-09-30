#pragma mark - Streamed scene assets

/* The iPhone host holds no app files: models arrive as bytes from the
 * packager (`_readFile`). SceneKit imports from disk, and an OBJ finds its
 * MTL and textures beside it, so Lua writes each streamed file here under
 * its project path and hands the scene the local path. */

// _stageAsset(projectPath, bytes) -> absolute path of the staged copy
static int bridge_stage_asset(lua_State *L) {
	NSString *relative = @(luaL_checkstring(L, 1));
	size_t length = 0;
	const char *bytes = luaL_checklstring(L, 2, &length);
	if ([relative.pathComponents containsObject:@".."]) return luaL_error(L, "asset path escapes its root: %s", relative.UTF8String);
	NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"lua-objc-assets"];
	NSString *path = [root stringByAppendingPathComponent:relative];
	NSError *error = nil;
	[NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
		withIntermediateDirectories:YES attributes:nil error:&error];
	if (!error) [[NSData dataWithBytes:bytes length:length] writeToFile:path options:NSDataWritingAtomic error:&error];
	if (error) return luaL_error(L, "cannot stage %s: %s", relative.UTF8String, error.localizedDescription.UTF8String);
	lua_pushstring(L, path.UTF8String);
	return 1;
}
