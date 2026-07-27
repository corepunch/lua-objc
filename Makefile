CC = clang
CFLAGS = -fobjc-arc -Wall -O2 $(shell pkg-config --cflags lua 2>/dev/null || echo "-I/opt/homebrew/include/lua")
HOST_CFLAGS = -Wall -O2
LDFLAGS = $(shell pkg-config --libs lua 2>/dev/null || echo "-L/opt/homebrew/lib -llua -lm") -framework Cocoa
MODULE_LDFLAGS = -dynamiclib -undefined dynamic_lookup
IOS_SIM_SDK = $(shell xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)

TARGET = lua-objc
HOST_SRC = src/host.c
APPKIT_RUNTIME_SRC = src/main.m
APPKIT_RUNTIME_DIRS = src/appkit src/shared
APPKIT_RUNTIME_FRAGMENTS = $(shell find $(APPKIT_RUNTIME_DIRS) -type f -name '*.m')
UIKIT_RUNTIME_SRC = src/uikit_module.m
UIKIT_RUNTIME_DIRS = src/uikit src/shared
UIKIT_RUNTIME_FRAGMENTS = $(shell find $(UIKIT_RUNTIME_DIRS) -type f -name '*.m')
NATIVE_PLUGIN = build/ide-controls.dylib
NATIVE_PLUGIN_SRC = src/ide_controls_plugin.m
FRAMEWORK_MODULES = build/AppKit.dylib build/IDEKit.dylib
IOS_FRAMEWORK_MODULE = $(if $(strip $(IOS_SIM_SDK)),build/UIKit.dylib)
EMBEDDED_LUA_DIR = lua/embedded
GENERATED_DIR = build/generated

all: $(TARGET) $(NATIVE_PLUGIN) $(FRAMEWORK_MODULES) $(IOS_FRAMEWORK_MODULE)

$(TARGET): $(HOST_SRC)
	$(CC) $(HOST_CFLAGS) -o $@ $<

$(NATIVE_PLUGIN): $(NATIVE_PLUGIN_SRC)
	mkdir -p build
	$(CC) $(CFLAGS) -dynamiclib -o $@ $^ $(LDFLAGS)

$(GENERATED_DIR)/%.lua.h: $(EMBEDDED_LUA_DIR)/%.lua
	mkdir -p $(GENERATED_DIR)
	xxd -i -n $*_lua $< $@

build/appkit-runtime.o: $(APPKIT_RUNTIME_SRC) $(APPKIT_RUNTIME_FRAGMENTS)
	mkdir -p build
	$(CC) $(CFLAGS) -fPIC -c -o $@ $<

build/appkit-module.o: src/embedded_lua_module.c $(GENERATED_DIR)/AppKit.lua.h
	mkdir -p build
	$(CC) $(CFLAGS) -fPIC -Ibuild \
		-DLUA_MODULE_OPEN=luaopen_AppKit \
		-DLUA_MODULE_BYTES=AppKit_lua \
		-DLUA_MODULE_LENGTH=AppKit_lua_len \
		-DLUA_MODULE_HEADER='"generated/AppKit.lua.h"' \
		-DLUA_MODULE_CHUNK_NAME='"@AppKit.lua"' \
		-c -o $@ $<

build/AppKit.dylib: build/appkit-runtime.o build/appkit-module.o
	$(CC) -dynamiclib -Wl,-install_name,@rpath/AppKit.dylib \
		-o $@ $^ $(LDFLAGS)

build/IDEKit.dylib: src/embedded_lua_module.c $(GENERATED_DIR)/IDEKit.lua.h
	mkdir -p build
	$(CC) $(CFLAGS) $(MODULE_LDFLAGS) -Ibuild \
		-DLUA_MODULE_OPEN=luaopen_IDEKit \
		-DLUA_MODULE_BYTES=IDEKit_lua \
		-DLUA_MODULE_LENGTH=IDEKit_lua_len \
		-DLUA_MODULE_HEADER='"generated/IDEKit.lua.h"' \
		-DLUA_MODULE_CHUNK_NAME='"@IDEKit.lua"' \
		-o $@ $<

build/UIKit.dylib: $(UIKIT_RUNTIME_SRC) $(UIKIT_RUNTIME_FRAGMENTS) $(GENERATED_DIR)/UIKit.lua.h
	@test -n "$(IOS_SIM_SDK)" || \
		{ echo "UIKit.dylib requires the iPhone Simulator SDK from Xcode"; exit 1; }
	mkdir -p build
	xcrun --sdk iphonesimulator $(CC) $(CFLAGS) $(MODULE_LDFLAGS) \
		-Ibuild -framework UIKit -framework Foundation -o $@ $(UIKIT_RUNTIME_SRC)

uikit: build/UIKit.dylib

run: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) $(ARGS)

run-hello: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/hello.lua

run-list: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/list.lua

run-live: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/live.lua

run-weather: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/weather.lua

run-welcome: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/welcome.lua

run-mail: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/mail.lua

run-layout: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/layout.lua

run-ide: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/ide.lua

TEST_FILES = $(wildcard tests/*.test.lua)

test: $(TARGET) $(NATIVE_PLUGIN) $(FRAMEWORK_MODULES)
	@passed=0; failed=0; \
	for t in $(TEST_FILES); do \
		echo "--- $$t ---"; \
		if ./$(TARGET) $$t 2>&1; then \
			passed=$$((passed + 1)); \
		else \
			failed=$$((failed + 1)); \
		fi; \
		echo ""; \
	done; \
	echo "$$((passed + failed)) test files: $$passed passed, $$failed failed"; \
	test $$failed -eq 0

clean:
	rm -f $(TARGET) $(NATIVE_PLUGIN) $(FRAMEWORK_MODULES) build/UIKit.dylib
	rm -f build/appkit-runtime.o build/appkit-module.o
	rm -f $(GENERATED_DIR)/AppKit.lua.h $(GENERATED_DIR)/IDEKit.lua.h $(GENERATED_DIR)/UIKit.lua.h

.PHONY: all uikit run clean test run-hello run-list run-live run-weather run-welcome run-mail run-layout
