#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* Resolve bundled code independently of the directory Finder launches from. */
int main(int argc, char **argv) {
	char executable[PATH_MAX], resources[PATH_MAX], runtime[PATH_MAX];
	uint32_t length = sizeof(executable);
	if (_NSGetExecutablePath(executable, &length)) return 1;
	snprintf(resources, sizeof(resources), "%s/../Resources", dirname(executable));
	if (chdir(resources)) { perror("Diskmap resources"); return 1; }
	snprintf(runtime, sizeof(runtime), "../Frameworks/AppKit.dylib");
	void *module = dlopen(runtime, RTLD_NOW | RTLD_GLOBAL);
	if (!module) { fprintf(stderr, "Diskmap: %s\n", dlerror()); return 1; }
	int (*run)(int, char **) = (int (*)(int, char **))dlsym(module, "lua_objc_main");
	if (!run) return 1;
	char **args = calloc((size_t)argc + 2, sizeof(char *));
	if (!args) return 1;
	args[0] = argv[0];
	args[1] = "apps/diskmap/init.lua";
	for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
	int status = run(argc + 1, args);
	free(args);
	return status;
}
