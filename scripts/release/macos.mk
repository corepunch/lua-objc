# Self-contained release runtime: vendored Lua, never Homebrew libraries.
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
ARCH ?= arm64
ROOT := build/release/native/macos-$(ARCH)
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
LUA := vendor/lua-5.4.8/src
LUA_SOURCES := $(filter-out $(LUA)/lua.c $(LUA)/luac.c,$(wildcard $(LUA)/*.c))
OBJECTS := $(patsubst $(LUA)/%.c,$(ROOT)/lua/%.o,$(LUA_SOURCES))
FLAGS := -arch $(ARCH) -isysroot $(SDK) -mmacosx-version-min=26.0 -O2 -g -Wall -DLUA_USE_MACOSX -I$(LUA)
FRAGMENTS := $(shell find src/appkit src/shared -name '*.m')
FRAMEWORKS := -framework Cocoa -framework WebKit -framework QuartzCore -framework Metal \
	-framework MetalKit -framework SceneKit -framework Symbols -framework UserNotifications -framework QuickLookUI
.PHONY: all
all: $(ROOT)/Launcher $(ROOT)/AppKit.dylib $(addprefix $(ROOT)/,$(addsuffix .dylib,$(PLUGINS)))
$(ROOT)/lua/%.o: $(LUA)/%.c scripts/release/macos.mk
	@mkdir -p $(@D)
	xcrun --sdk macosx clang $(FLAGS) -fPIC -c $< -o $@
$(ROOT)/runtime.o: src/main.m $(FRAGMENTS) scripts/release/macos.mk
	@mkdir -p $(@D)
	xcrun --sdk macosx clang $(FLAGS) -fobjc-arc -fPIC -c $< -o $@
$(ROOT)/module.o: src/embedded_lua_module.c scripts/release/macos.mk
	@mkdir -p $(@D)
	xcrun --sdk macosx clang $(FLAGS) -fPIC -c $< -o $@
$(ROOT)/AppKit.dylib: $(ROOT)/runtime.o $(ROOT)/module.o $(OBJECTS)
	xcrun --sdk macosx clang $(FLAGS) -dynamiclib -Wl,-install_name,@rpath/AppKit.dylib $^ $(FRAMEWORKS) -o $@
$(ROOT)/Launcher.o: scripts/launcher/launcher.c scripts/release/macos.mk
	@mkdir -p $(@D)
	xcrun --sdk macosx clang $(FLAGS) -c $< -o $@
$(ROOT)/Launcher: $(ROOT)/Launcher.o
	xcrun --sdk macosx clang $(FLAGS) $< -framework CoreFoundation -Wl,-needed_framework,CoreServices -o $@
$(ROOT)/StorageScan.o: src/plugins/storage/StorageScan.m src/plugins/storage/Duplicates.m scripts/release/macos.mk
	@mkdir -p $(@D)
	xcrun --sdk macosx clang $(FLAGS) -fobjc-arc -fPIC -c $< -o $@
$(ROOT)/StorageScan.dylib: $(ROOT)/StorageScan.o
	xcrun --sdk macosx clang $(FLAGS) -dynamiclib -undefined dynamic_lookup \
		-Wl,-install_name,@rpath/StorageScan.dylib $< -framework Foundation -lcompression -o $@
$(ROOT)/AudioStream.o: src/plugins/audio/AudioStream.m scripts/release/macos.mk
	@mkdir -p $(@D)
	xcrun --sdk macosx clang $(FLAGS) -fobjc-arc -fPIC -c $< -o $@
$(ROOT)/AudioStream.dylib: $(ROOT)/AudioStream.o
	xcrun --sdk macosx clang $(FLAGS) -dynamiclib -undefined dynamic_lookup \
		-Wl,-install_name,@rpath/AudioStream.dylib $< -framework Foundation -framework AVFAudio -framework Accelerate -o $@
