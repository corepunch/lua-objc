#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/*
 * The executable of every bundled lua-objc app (apps/<name>/<Name>.xcodeproj).
 * It runs the Lua entry point the bundle's Info.plist names under
 * `LuaObjCEntry` ("apps/diskmap/init.lua"), so an app's project needs no
 * launcher of its own. Bundled code resolves from Contents/Resources,
 * independently of the directory Finder launches from.
 *
 * An app target links this launcher against CoreServices on purpose
 * (OTHER_LDFLAGS = -Wl,-needed_framework,CoreServices). Inside the App
 * Sandbox, LaunchServices only receives its launchservicesd mach-lookup
 * extension when it is loaded as part of process startup; if AppKit and
 * LaunchServices first arrive through the dlopen below, _RegisterApplication
 * is denied the lookup and abort()s inside +[NSApplication sharedApplication].
 */
int main(int argc, char **argv) {
	char executable[PATH_MAX], resources[PATH_MAX], entry[PATH_MAX];
	uint32_t length = sizeof(executable);
	if (_NSGetExecutablePath(executable, &length)) return 1;
	CFTypeRef value = CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), CFSTR("LuaObjCEntry"));
	if (!value || CFGetTypeID(value) != CFStringGetTypeID()
			|| !CFStringGetCString(value, entry, sizeof(entry), kCFStringEncodingUTF8)) {
		fprintf(stderr, "%s: Info.plist names no LuaObjCEntry\n", argv[0]);
		return 1;
	}
	snprintf(resources, sizeof(resources), "%s/../Resources", dirname(executable));
	if (chdir(resources)) { perror("resources"); return 1; }
	void *module = dlopen("../Frameworks/AppKit.dylib", RTLD_NOW | RTLD_GLOBAL);
	if (!module) { fprintf(stderr, "%s\n", dlerror()); return 1; }
	int (*run)(int, char **) = (int (*)(int, char **))dlsym(module, "lua_objc_main");
	if (!run) return 1;
	char **args = calloc((size_t)argc + 2, sizeof(char *));
	if (!args) return 1;
	args[0] = argv[0];
	args[1] = entry;
	for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
	int status = run(argc + 1, args);
	free(args);
	return status;
}
