#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int (*LuaObjCMain)(int argc, char *argv[]);

static void framework_path(char *destination, size_t capacity) {
	const char *override = getenv("LUA_OBJC_APPKIT_MODULE");
	if (override && override[0] != '\0') {
		snprintf(destination, capacity, "%s", override);
		return;
	}

	char executable[PATH_MAX];
	uint32_t length = (uint32_t)sizeof(executable);
	if (_NSGetExecutablePath(executable, &length) != 0) {
		snprintf(destination, capacity, "build/AppKit.dylib");
		return;
	}

	char resolved[PATH_MAX];
	if (!realpath(executable, resolved)) {
		snprintf(resolved, sizeof(resolved), "%s", executable);
	}
	char directoryBuffer[PATH_MAX];
	snprintf(directoryBuffer, sizeof(directoryBuffer), "%s", resolved);
	snprintf(destination, capacity, "%s/build/AppKit.dylib",
		dirname(directoryBuffer));
}

int main(int argc, char *argv[]) {
	char path[PATH_MAX];
	framework_path(path, sizeof(path));

	/*
	 * RTLD_GLOBAL lets Lua-loaded companion modules resolve Lua symbols and
	 * the private AppKitNative entry point from the framework runtime.
	 */
	void *framework = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
	if (!framework) {
		fprintf(stderr, "lua-objc: cannot load %s: %s\n", path, dlerror());
		return 1;
	}

	LuaObjCMain run = (LuaObjCMain)dlsym(framework, "lua_objc_main");
	if (!run) {
		fprintf(stderr, "lua-objc: AppKit module has no lua_objc_main: %s\n",
			dlerror());
		dlclose(framework);
		return 1;
	}

	int status = run(argc, argv);
	dlclose(framework);
	return status;
}
