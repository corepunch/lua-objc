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
FRAMEWORK_MODULES = build/AppKit.dylib
IOS_FRAMEWORK_MODULE = $(if $(strip $(IOS_SIM_SDK)),build/UIKit.dylib)
EMBEDDED_LUA_DIR = lua/embedded
GENERATED_DIR = build/generated

all: $(TARGET) $(FRAMEWORK_MODULES) $(IOS_FRAMEWORK_MODULE)

$(TARGET): $(HOST_SRC)
	$(CC) $(HOST_CFLAGS) -o $@ $<

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

build/UIKit.dylib: $(UIKIT_RUNTIME_SRC) $(UIKIT_RUNTIME_FRAGMENTS) $(GENERATED_DIR)/UIKit.lua.h
	@test -n "$(IOS_SIM_SDK)" || \
		{ echo "UIKit.dylib requires the iPhone Simulator SDK from Xcode"; exit 1; }
	mkdir -p build
	xcrun --sdk iphonesimulator $(CC) $(CFLAGS) $(MODULE_LDFLAGS) \
		-Ibuild -framework UIKit -framework Foundation -framework QuartzCore -o $@ $(UIKIT_RUNTIME_SRC)

uikit: build/UIKit.dylib

run: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) $(ARGS)

run-hello: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/hello/init.lua

run-list: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/list/init.lua

run-stocks: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/stocks/init.lua

run-weather: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/weather/init.lua

run-welcome: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/welcome/init.lua

run-mail: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/mail/init.lua

run-layout: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/layout/init.lua

run-ide: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) examples/ide/init.lua

TEST_FILES = $(wildcard tests/*.test.lua)

test: $(TARGET) $(FRAMEWORK_MODULES)
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

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
IOS_MIN := 26.5
DEVICE ?= iPhone 17
IOS_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
IOS_CC := $(shell xcrun --sdk iphonesimulator --find clang)
LUA_SRC_DIR := third_party/lua-5.4.8/src
LUA_CORE := lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject \
	lopcodes lparser lstate lstring ltable ltm lundump lvm lzio
LUA_LIB := lauxlib lbaselib lcorolib ldblib liolib lmathlib loadlib loslib \
	lstrlib ltablib lutf8lib linit
LUA_OBJS := $(addprefix build/ios/lua/,$(addsuffix .o,$(LUA_CORE) $(LUA_LIB)))
IOS_LUA_A := build/ios/liblua.a
HOST_BUNDLE := build/ios/LuaObjCHost.app
HOST_BINARY := $(HOST_BUNDLE)/LuaObjCHost
PACKAGER := build/lua-objc-packager
IOS_HOST_SRCS := ios/LuaObjCHost/main.m ios/LuaObjCHost/AppDelegate.m \
	ios/LuaObjCHost/SceneDelegate.m ios/LuaObjCHost/LuaHost.m \
	ios/LuaObjCHost/LuaCapture.m \
	ios/LuaObjCHost/LuaSourceLoader.m ios/LuaObjCHost/LuaHotClient.m \
	ios/LuaObjCHost/LuaErrorOverlay.m
IOS_CFLAGS_C := -Wall -O2 -isysroot $(IOS_SDK) -arch arm64 \
	-mios-simulator-version-min=$(IOS_MIN) -DLUA_USE_IOS \
	-I$(LUA_SRC_DIR)
IOS_CFLAGS := -fobjc-arc $(IOS_CFLAGS_C) \
	-Iios/LuaObjCHost -Isrc -Ibuild

build/ios/lua/%.o: $(LUA_SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	@if [ "$*" = "lapi" ]; then echo "Compiling Lua 5.4..."; fi
	@$(IOS_CC) $(IOS_CFLAGS_C) -c -o $@ $<

$(IOS_LUA_A): $(LUA_OBJS)
	@echo "Linking Lua 5.4 runtime..."
	@libtool -static -o $@ $^

$(PACKAGER): src/packager/packager.m lua/packager/paths.lua
	mkdir -p build
	$(CC) -fobjc-arc -Wall -O2 \
		$(shell pkg-config --cflags lua 2>/dev/null || echo "-I/opt/homebrew/include/lua") \
		-o $@ src/packager/packager.m \
		$(shell pkg-config --libs lua 2>/dev/null || echo "-L/opt/homebrew/lib -llua") \
		-framework Foundation -framework CoreServices

$(HOST_BINARY): $(IOS_LUA_A) $(IOS_HOST_SRCS) ios/LuaObjCHost/LuaObjCHost.h $(UIKIT_RUNTIME_SRC) \
		$(UIKIT_RUNTIME_FRAGMENTS) $(GENERATED_DIR)/UIKit.lua.h \
		ios/LuaObjCHost/Info.plist ios/LuaObjCHost/AppIcon.png
	@test -n "$(IOS_SDK)" || { echo "iPhone Simulator SDK missing; set DEVELOPER_DIR"; exit 1; }
	@echo "Building iOS host..."
	@mkdir -p $(HOST_BUNDLE)
	@$(IOS_CC) $(IOS_CFLAGS) \
		-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
		-o $(HOST_BUNDLE)/LuaObjCHost \
		$(IOS_HOST_SRCS) $(UIKIT_RUNTIME_SRC) $(IOS_LUA_A)
	@cp ios/LuaObjCHost/Info.plist $(HOST_BUNDLE)/Info.plist
	@cp ios/LuaObjCHost/AppIcon.png $(HOST_BUNDLE)/AppIcon.png
	@printf 'APPL????' > $(HOST_BUNDLE)/PkgInfo
	@codesign --sign - --force --entitlements /dev/null $(HOST_BUNDLE) 2>/dev/null \
		|| codesign --sign - --force $(HOST_BUNDLE)

ios-host: $(HOST_BINARY)
ios-packager: $(PACKAGER)

ios-packager-run: ios-packager
	./$(PACKAGER) --root "$(CURDIR)" --port 8081 --entry "$(or $(PROJECT),examples/hello)"

ios-packager-stop:
	@if [ -f build/ios/packager.pid ]; then kill $$(cat build/ios/packager.pid) 2>/dev/null || true; rm -f build/ios/packager.pid; fi

ios-run: ios-host ios-packager
	chmod +x scripts/ios-run.sh
	DEVELOPER_DIR=$(DEVELOPER_DIR) DEVICE="$(DEVICE)" PROJECT="$(or $(PROJECT),examples/hello)" \
		scripts/ios-run.sh

ios-internal-screenshot: ios-host ios-packager
	DEVELOPER_DIR=$(DEVELOPER_DIR) OUT="$(or $(OUT),/tmp/ios-internal-screenshot.png)" \
		PROJECT="$(or $(PROJECT),examples/hello)" DEVICE="$(DEVICE)" \
		scripts/ios-internal-screenshot.sh

ios-screenshot:
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun simctl io booted screenshot \
		$(or $(OUT),/tmp/ios-screenshot.png)

ios: ios-run

ios-reset:
	@killall Simulator 2>/dev/null || true
	@xcrun simctl shutdown all 2>/dev/null || true
	@xcrun simctl erase all 2>/dev/null || true
	@echo "ios-reset: simulator shut down and erased"

clean:
	@rm -f $(TARGET) $(FRAMEWORK_MODULES) build/UIKit.dylib
	@rm -f build/appkit-runtime.o build/appkit-module.o
	@rm -f $(GENERATED_DIR)/AppKit.lua.h $(GENERATED_DIR)/UIKit.lua.h
	@rm -rf build/ios $(PACKAGER)

screenshot: $(TARGET) $(FRAMEWORK_MODULES)
	./$(TARGET) --screenshot=$(or $(OUT),/tmp/screenshot.png) $(ARGS)

parity-check:
	python3 scripts/parity/validate_manifest.py

parity-case: parity-check $(TARGET) $(FRAMEWORK_MODULES)
	CASE=$(CASE) scripts/parity/capture_macos_case.sh

parity-report: parity-check
	@test -n "$(CASE)" || (echo "usage: make parity-report CASE=<id> REFERENCE_JSON=<path>" >&2; exit 2)
	@test -n "$(REFERENCE_JSON)" || (echo "parity-report: REFERENCE_JSON is required" >&2; exit 2)
	python3 scripts/parity/report_case.py \
		--candidate-xml "build/parity/macos/$(CASE)/candidate.xml" \
		--candidate-png "build/parity/macos/$(CASE)/candidate.png" \
		--reference-json "$(REFERENCE_JSON)" \
		$(if $(REFERENCE_PNG),--reference-png "$(REFERENCE_PNG)") \
		--out "build/parity/macos/$(CASE)/report.json" --strict

.PHONY: all uikit run clean test parity-check parity-case parity-report run-hello run-list run-live run-weather run-welcome run-mail run-layout screenshot ios-host ios-packager ios-packager-run ios-run ios-internal-screenshot ios-screenshot ios ios-reset
