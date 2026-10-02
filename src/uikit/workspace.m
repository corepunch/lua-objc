#pragma mark - HTTP requests

static int bridge_http_request(lua_State *L) {
	NSURL *url = [NSURL URLWithString:@(luaL_checkstring(L, 1))];
	if (!url || ![url.scheme isEqualToString:@"https"]) return luaL_error(L, "HTTP request requires HTTPS");
	luaL_checktype(L, 4, LUA_TFUNCTION);
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	request.timeoutInterval = 120;
	request.allHTTPHeaderFields = lua_to_objc_value(L, 2);
	request.HTTPBody = [@(luaL_checkstring(L, 3)) dataUsingEncoding:NSUTF8StringEncoding];
	LuaStateOwner *owner = owner_for_state(L);
	if (!owner) return luaL_error(L, "async runtime is not initialized");
	LuaReg *reg = lua_reg_create(L, 4, YES);
	__block NSURLSessionDataTask *task = nil;
	task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[owner _untrack:task];
			task = nil;
			lua_State *callL = lua_reg_live_state(reg);
			if (callL && !owner.cancelled) {
				lua_reg_push(reg);
				NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
				if (body) lua_pushstring(callL, body.UTF8String); else lua_pushnil(callL);
				if (error) lua_pushstring(callL, error.localizedDescription.UTF8String); else lua_pushnil(callL);
				lua_pushinteger(callL, [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0);
				lua_objc_pcall(callL, 3, 0, "HTTP request");
			}
			[reg dispose];
		});
	}];
	[owner trackTask:task];
	[task resume];
	push_objc(L, task, "nsobject");
	return 1;
}
static int bridge_cancel_request(lua_State *L) {
	id task = check_objc(L, 1);
	if (![task isKindOfClass:NSURLSessionTask.class]) return luaL_error(L, "expected HTTP request");
	[task cancel];
	return 0;
}
static int bridge_focus(lua_State *L) {
	UIView *view = check_objc(L, 1);
	[view becomeFirstResponder];
	return 0;
}
