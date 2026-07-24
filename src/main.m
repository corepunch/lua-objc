#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static char kAxisKey;
static const CGFloat kPadding = 12.0;

typedef struct {
    void *ptr;
} ObjCRef;

static void push_objc(lua_State *L, id obj, const char *meta) {
    ObjCRef *ref = lua_newuserdata(L, sizeof(ObjCRef));
    ref->ptr = (void *)CFBridgingRetain(obj);
    luaL_setmetatable(L, meta);
}

static id check_objc(lua_State *L, int idx) {
    ObjCRef *ref = luaL_testudata(L, idx, "nsview");
    if (ref) return (__bridge id)ref->ptr;
    ref = luaL_testudata(L, idx, "nswindow");
    if (ref) return (__bridge id)ref->ptr;
    luaL_typeerror(L, idx, "nsview or nswindow");
    return nil;
}

static NSView *check_view(lua_State *L, int idx) {
    id obj = check_objc(L, idx);
    if ([obj isKindOfClass:[NSWindow class]]) {
        return [(NSWindow *)obj contentView];
    }
    return (NSView *)obj;
}

static int gc_objc(lua_State *L) {
    ObjCRef *ref = lua_touserdata(L, 1);
    if (ref->ptr) {
        CFRelease(ref->ptr);
        ref->ptr = NULL;
    }
    return 0;
}

static int bridge_window(lua_State *L) {
    const char *title = luaL_checkstring(L, 1);
    CGFloat width = luaL_checknumber(L, 2);
    CGFloat height = luaL_checknumber(L, 3);

    NSRect frame = NSMakeRect(0, 0, width, height);
    NSUInteger style = NSWindowStyleMaskTitled
                     | NSWindowStyleMaskClosable
                     | NSWindowStyleMaskMiniaturizable
                     | NSWindowStyleMaskResizable;

    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    w.title = [NSString stringWithUTF8String:title];
    w.releasedWhenClosed = NO;
    [w center];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSWindowWillCloseNotification
                    object:w
                     queue:nil
                usingBlock:^(NSNotification *note) {
                    [NSApp terminate:nil];
                }];

    push_objc(L, w, "nswindow");
    return 1;
}

static int bridge_vstack(lua_State *L) {
    NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
    objc_setAssociatedObject(v, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
    push_objc(L, v, "nsview");
    return 1;
}

static int bridge_hstack(lua_State *L) {
    NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
    objc_setAssociatedObject(v, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
    push_objc(L, v, "nsview");
    return 1;
}

static int bridge_spacer(lua_State *L) {
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    push_objc(L, v, "nsview");
    return 1;
}

static int bridge_text(lua_State *L) {
    const char *str = luaL_checkstring(L, 1);

    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)];
    tf.stringValue = [NSString stringWithUTF8String:str];
    tf.bezeled = NO;
    tf.drawsBackground = NO;
    tf.editable = NO;
    tf.selectable = NO;
    [tf sizeToFit];

    push_objc(L, tf, "nsview");
    return 1;
}

static int bridge_image(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    NSString *nsPath = [NSString stringWithUTF8String:path];

    NSImage *img = [[NSImage alloc] initWithContentsOfFile:nsPath];
    if (!img) {
        img = [NSImage imageNamed:nsPath];
    }
    if (!img) {
        return luaL_error(L, "failed to load image: %s", path);
    }

    NSSize size = img.size;
    if (size.width > 400) {
        CGFloat ratio = 400.0 / size.width;
        size.width = 400;
        size.height *= ratio;
    }

    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    iv.image = img;
    iv.imageScaling = NSImageScaleProportionallyUpOrDown;

    push_objc(L, iv, "nsview");
    return 1;
}

static int bridge_add(lua_State *L) {
    id parent = check_objc(L, 1);
    NSView *child = check_view(L, 2);

    NSView *container;
    if ([parent isKindOfClass:[NSWindow class]]) {
        container = [(NSWindow *)parent contentView];
    } else {
        container = (NSView *)parent;
    }

    [container addSubview:child];
    return 0;
}

static void layout_recursive(NSView *view, CGFloat width) {
    if (!view) return;

    NSString *axis = objc_getAssociatedObject(view, &kAxisKey);

    if ([axis isEqualToString:@"vstack"]) {
        CGFloat y = kPadding;
        for (NSView *sv in view.subviews) {
            [(id)sv sizeToFit];
            NSRect f = sv.frame;
            CGFloat childW = f.size.width > 0 ? f.size.width : width - 2 * kPadding;
            CGFloat childH = f.size.height > 0 ? f.size.height : 22;
            sv.frame = NSMakeRect(kPadding, y, childW, childH);
            y += childH + kPadding;
            layout_recursive(sv, childW);
        }
        view.frame = NSMakeRect(0, 0, width, y);
    } else if ([axis isEqualToString:@"hstack"]) {
        CGFloat x = kPadding;
        CGFloat maxH = 0;
        for (NSView *sv in view.subviews) {
            [(id)sv sizeToFit];
            NSRect f = sv.frame;
            CGFloat childW = f.size.width > 0 ? f.size.width : 40;
            CGFloat childH = f.size.height > 0 ? f.size.height : 22;
            sv.frame = NSMakeRect(x, kPadding, childW, childH);
            if (childH > maxH) maxH = childH;
            x += childW + kPadding;
            layout_recursive(sv, childW);
        }
        view.frame = NSMakeRect(0, 0, x, maxH + 2 * kPadding);
    } else {
        for (NSView *sv in view.subviews) {
            layout_recursive(sv, width);
        }
    }
}

static int bridge_layout(lua_State *L) {
    id obj = check_objc(L, 1);
    CGFloat width = luaL_optnumber(L, 2, 400);

    NSView *view;
    if ([obj isKindOfClass:[NSWindow class]]) {
        view = [(NSWindow *)obj contentView];
    } else {
        view = (NSView *)obj;
    }

    layout_recursive(view, width);
    return 0;
}

static int bridge_set_frame(lua_State *L) {
    NSView *view = check_view(L, 1);
    CGFloat x = luaL_checknumber(L, 2);
    CGFloat y = luaL_checknumber(L, 3);
    CGFloat w = luaL_checknumber(L, 4);
    CGFloat h = luaL_checknumber(L, 5);
    view.frame = NSMakeRect(x, y, w, h);
    return 0;
}

static int bridge_get_frame(lua_State *L) {
    NSView *view = check_view(L, 1);
    NSRect f = view.frame;
    lua_pushnumber(L, f.origin.x);
    lua_pushnumber(L, f.origin.y);
    lua_pushnumber(L, f.size.width);
    lua_pushnumber(L, f.size.height);
    return 4;
}

static int bridge_set_content_size(lua_State *L) {
    id obj = check_objc(L, 1);
    CGFloat width = luaL_checknumber(L, 2);
    CGFloat height = luaL_checknumber(L, 3);

    if ([obj isKindOfClass:[NSWindow class]]) {
        NSWindow *w = (NSWindow *)obj;
        NSRect frame = w.frame;
        NSRect contentRect = [w contentRectForFrameRect:frame];
        contentRect.size = NSMakeSize(width, height);
        NSRect newFrame = [w frameRectForContentRect:contentRect];
        [w setFrame:newFrame display:YES animate:NO];
    } else {
        NSView *v = (NSView *)obj;
        v.frame = NSMakeRect(v.frame.origin.x, v.frame.origin.y, width, height);
    }
    return 0;
}

static int ui_env_index(lua_State *L) {
    lua_getfield(L, LUA_REGISTRYINDEX, "ui_module");
    lua_pushvalue(L, 2);
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 2);

    lua_getglobal(L, lua_tostring(L, 2));
    return 1;
}

static int bridge_show(lua_State *L) {
    NSWindow *w = (__bridge NSWindow *)((ObjCRef *)lua_touserdata(L, 1))->ptr;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [w makeKeyAndOrderFront:nil];
    [NSApp run];

    return 0;
}

static const luaL_Reg bridge_lib[] = {
    {"_window",           bridge_window},
    {"_vstack",           bridge_vstack},
    {"_hstack",           bridge_hstack},
    {"_spacer",           bridge_spacer},
    {"_text",             bridge_text},
    {"_image",            bridge_image},
    {"_add",              bridge_add},
    {"_layout",           bridge_layout},
    {"_set_frame",        bridge_set_frame},
    {"_get_frame",        bridge_get_frame},
    {"_set_content_size", bridge_set_content_size},
    {"_show",             bridge_show},
    {NULL, NULL},
};

static void register_metatable(lua_State *L, const char *name) {
    luaL_newmetatable(L, name);
    lua_pushcfunction(L, gc_objc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);
}

int luaopen_bridge(lua_State *L) {
    register_metatable(L, "nsview");
    register_metatable(L, "nswindow");
    luaL_newlib(L, bridge_lib);
    return 1;
}

int main(int argc, char *argv[]) {
    [NSApplication sharedApplication];

    lua_State *L = luaL_newstate();
    luaL_openlibs(L);

    luaL_requiref(L, "bridge", luaopen_bridge, 1);
    lua_pop(L, 1);

    char cwd[4096];
    if (getcwd(cwd, sizeof(cwd))) {
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "path");
        const char *defpath = lua_tostring(L, -1);
        char newpath[8192];
        snprintf(newpath, sizeof(newpath), "%s;%s/?.lua;%s/lua/?.lua", defpath, cwd, cwd);
        lua_pushstring(L, newpath);
        lua_setfield(L, -3, "path");
        lua_pop(L, 2);
    }

    lua_getglobal(L, "require");
    lua_pushstring(L, "UI");
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        fprintf(stderr, "error loading UI: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }
    lua_setfield(L, LUA_REGISTRYINDEX, "ui_module");

    lua_newtable(L);
    lua_newtable(L);
    lua_pushcfunction(L, ui_env_index);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);

    const char *script = argc > 1 ? argv[1] : "examples/hello.lua";
    if (luaL_loadfile(L, script) != LUA_OK) {
        fprintf(stderr, "error: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_insert(L, -2);

    if (lua_setupvalue(L, -2, 1) == NULL) {
        lua_pop(L, 1);
        fprintf(stderr,
            "error: script has no _ENV upvalue (require Lua 5.2+)\n");
        lua_close(L);
        return 1;
    }

    if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
        fprintf(stderr, "error: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
