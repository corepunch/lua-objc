CC = clang
CFLAGS = -fobjc-arc -Wall -O2 $(shell pkg-config --cflags lua 2>/dev/null || echo "-I/opt/homebrew/include/lua")
HOST_CFLAGS = -Wall -O2
LDFLAGS = $(shell pkg-config --libs lua 2>/dev/null || echo "-L/opt/homebrew/lib -llua -lm") -framework Cocoa -framework WebKit -framework QuartzCore -framework Metal -framework MetalKit -framework SceneKit -framework GameController -framework Symbols -framework UserNotifications -framework QuickLookUI -framework AVFAudio -framework UniformTypeIdentifiers
MODULE_LDFLAGS = -dynamiclib -undefined dynamic_lookup
IOS_SIM_SDK = $(shell xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
# UIKit.dylib gets Lua API definitions from its host; keep only those imports
# dynamically looked up while linking all platform frameworks directly.
IOS_LUA_LOOKUP_SYMBOLS = \
	_luaL_argerror _luaL_checkinteger _luaL_checklstring _luaL_checknumber \
	_luaL_checktype _luaL_checkudata _luaL_checkversion_ _luaL_error \
	_luaL_len _luaL_loadbufferx _luaL_newmetatable _luaL_optinteger \
	_luaL_optlstring _luaL_optnumber _luaL_ref _luaL_requiref _luaL_setfuncs \
	_luaL_setmetatable _luaL_testudata _luaL_typeerror _luaL_unref \
	_lua_absindex _lua_close _lua_copy _lua_createtable _lua_error _lua_gc \
	_lua_getfield _lua_geti _lua_gettop _lua_isinteger _lua_isnumber \
	_lua_isstring _lua_newuserdatauv _lua_next _lua_pcallk _lua_pushboolean \
	_lua_pushcclosure _lua_pushfstring _lua_pushinteger _lua_pushlightuserdata \
	_lua_pushlstring _lua_pushnil _lua_pushnumber _lua_pushstring _lua_pushvalue \
	_lua_rawget _lua_rawgeti _lua_rawlen _lua_rawset _lua_rawseti _lua_rotate \
	_lua_setfield _lua_setmetatable _lua_settable _lua_settop _lua_toboolean \
	_lua_tointegerx _lua_tolstring _lua_tonumberx _lua_topointer _lua_touserdata \
	_lua_type _lua_typename
comma := ,
IOS_LUA_LOOKUP_FLAGS = $(foreach symbol,$(IOS_LUA_LOOKUP_SYMBOLS),-Wl$(comma)-U$(comma)$(symbol))

LUA_OBJC_BIN = lua-objc
HOST_SRC = src/host.c
APPKIT_RUNTIME_SRC = src/main.m
APPKIT_RUNTIME_DIRS = src/appkit src/shared
APPKIT_RUNTIME_FRAGMENTS = $(shell find $(APPKIT_RUNTIME_DIRS) -type f -name '*.m')
UIKIT_RUNTIME_SRC = src/uikit_module.m
UIKIT_RUNTIME_DIRS = src/uikit src/shared
UIKIT_RUNTIME_FRAGMENTS = $(shell find $(UIKIT_RUNTIME_DIRS) -type f -name '*.m')
FRAMEWORK_MODULES = build/AppKit.dylib
NATIVE_PLUGINS = build/StorageScan.dylib build/AudioStream.dylib build/AudioFile.dylib build/ReelNative.dylib build/Git.dylib
IOS_FRAMEWORK_MODULE = $(if $(strip $(IOS_SIM_SDK)),build/UIKit.dylib)
EMBEDDED_LUA_DIR = lua/embedded
GENERATED_DIR = build/generated
PARITY_IMAGE_DIFF = build/parity/image_diff

all: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(IOS_FRAMEWORK_MODULE) $(NATIVE_PLUGINS)

$(LUA_OBJC_BIN): $(HOST_SRC)
	$(CC) $(HOST_CFLAGS) -o $@ $<

$(GENERATED_DIR)/%.lua.h: $(EMBEDDED_LUA_DIR)/%.lua
	mkdir -p $(GENERATED_DIR)
	xxd -i -n $*_lua $< $@

build/appkit-runtime.o: $(APPKIT_RUNTIME_SRC) $(APPKIT_RUNTIME_FRAGMENTS)
	mkdir -p build
	$(CC) $(CFLAGS) -fPIC -c -o $@ $<

build/appkit-module.o: src/embedded_lua_module.c
	mkdir -p build
	$(CC) $(CFLAGS) -fPIC -c -o $@ $<

build/AppKit.dylib: build/appkit-runtime.o build/appkit-module.o
	$(CC) -dynamiclib -Wl,-install_name,@rpath/AppKit.dylib \
		-o $@ $^ $(LDFLAGS)

build/UIKit.dylib: $(UIKIT_RUNTIME_SRC) $(UIKIT_RUNTIME_FRAGMENTS) $(GENERATED_DIR)/UIKit.lua.h
	@test -n "$(IOS_SIM_SDK)" || \
		{ echo "UIKit.dylib requires the iPhone Simulator SDK from Xcode"; exit 1; }
	mkdir -p build
	xcrun --sdk iphonesimulator $(CC) $(CFLAGS) -dynamiclib $(IOS_LUA_LOOKUP_FLAGS) \
		-Ibuild -framework UIKit -framework CoreGraphics -framework CoreText -framework WebKit -framework SceneKit -framework GameController \
		-framework Foundation -framework QuartzCore -framework Symbols -framework UserNotifications \
		-framework Security -framework AVFAudio -framework AVFoundation \
		-o $@ $(UIKIT_RUNTIME_SRC)

uikit: build/UIKit.dylib

build/StorageScan.dylib: src/plugins/storage/StorageScan.m src/plugins/storage/Duplicates.m Makefile
	mkdir -p build
	$(CC) $(CFLAGS) -mmacosx-version-min=26.0 $(MODULE_LDFLAGS) -framework Foundation -lcompression -o $@ $<

build/AudioStream.dylib: src/plugins/audio/AudioStream.m Makefile
	mkdir -p build
	$(CC) $(CFLAGS) -mmacosx-version-min=26.0 $(MODULE_LDFLAGS) -framework Foundation -framework AVFAudio -framework Accelerate -o $@ $<

build/AudioFile.dylib: src/plugins/audio/AudioFile.m Makefile
	mkdir -p build
	$(CC) $(CFLAGS) -mmacosx-version-min=26.0 $(MODULE_LDFLAGS) -framework Foundation -framework AVFAudio -o $@ $<

# The Reel motion package's native half (modules/reel): offscreen drawing,
# images and H.264. Standalone like StorageScan; the runtime never loads it.
build/ReelNative.dylib: modules/reel/native/ReelNative.m modules/reel/native/scene.m src/shared/scene_models.m Makefile
	mkdir -p build
	$(CC) $(CFLAGS) -mmacosx-version-min=26.0 $(MODULE_LDFLAGS) -framework AppKit -framework AVFoundation \
		-framework CoreMedia -framework CoreVideo -framework CoreText -framework ImageIO \
		-framework SceneKit -framework GameController -framework Metal \
		-framework UniformTypeIdentifiers -o $@ $<

# libgit2 (vendor/libgit2) as a static library per SDK and architecture.
LIBGIT2_INCLUDE = vendor/libgit2/include
LIBGIT2_LIBS = -lz -framework Security -framework CoreFoundation
# The compiled library is immutable for a pinned source revision, platform,
# architecture and set of compiler inputs, so it is built once into a cache
# shared by every worktree and cloned (APFS copy-on-write, no extra storage)
# into each build/ folder. Mutable outputs stay in the worktree's own build/.
DEP_CACHE ?= $(HOME)/Library/Caches/lua-objc
LIBGIT2_KEY = $(shell { git -C vendor/libgit2 rev-parse HEAD; cat scripts/libgit2/libgit2.mk scripts/libgit2/git2_features.h scripts/libgit2/pcre2_config.h; xcrun clang --version; } 2>/dev/null | shasum | cut -c1-16)
build/libgit2/%/libgit2.a: scripts/libgit2/libgit2.mk scripts/libgit2/git2_features.h scripts/libgit2/pcre2_config.h
	@cached="$(DEP_CACHE)/libgit2/$(LIBGIT2_KEY)/$*/libgit2.a"; \
	if [ -f "$$cached" ]; then mkdir -p $(dir $@) && cp -c "$$cached" $@ && touch $@ && echo "libgit2 $*: reused from cache"; \
	else \
		$(MAKE) -j$(shell getconf _NPROCESSORS_ONLN) -f scripts/libgit2/libgit2.mk SDK=$(firstword $(subst -, ,$*)) ARCH=$(lastword $(subst -, ,$*)) OUT=build/libgit2/$* \
		&& mkdir -p "$$(dirname $$cached)" && cp -c $@ "$$cached"; \
	fi

MAC_ARCH := $(shell uname -m)
build/Git.dylib: src/plugins/git/Git.c build/libgit2/macosx-$(MAC_ARCH)/libgit2.a Makefile
	mkdir -p build
	$(CC) -Wall -O2 $(shell pkg-config --cflags lua 2>/dev/null || echo "-I/opt/homebrew/include/lua") \
		-I$(LIBGIT2_INCLUDE) -mmacosx-version-min=26.0 $(MODULE_LDFLAGS) -o $@ $< \
		build/libgit2/macosx-$(MAC_ARCH)/libgit2.a $(LIBGIT2_LIBS) -liconv

run: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	./$(LUA_OBJC_BIN) $(ARGS)

run-hello: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) demo/hello/init.lua

run-list: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) demo/list/init.lua

run-stocks: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) apps/stocks/init.lua

run-weather: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) apps/weather/init.lua

run-welcome: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) demo/welcome/init.lua

run-mail: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) demo/mail/init.lua

run-layout: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) demo/layout/init.lua

run-ide: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) demo/ide/init.lua

# Usage: make run-diskmap                      # scans this repo (~28ms)
#        make run-diskmap DIR=~/Developer/icui  # scan a specific dir
run-diskmap: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	./$(LUA_OBJC_BIN) apps/diskmap/init.lua $(or $(DIR),$(CURDIR))

# Diskmap against a saved snapshot of a disk (apps/diskmap/README.md, "Mock HDD").
# Usage: make diskmap-mock-export   # snapshot this Mac; keep the window open
#                                   # until it says "Saved N file names…"
#        make diskmap-mock          # open Diskmap on that snapshot
#        make diskmap-mock MOCK=/path/to/other.bin
#        make diskmap-showcase      # the bundled synthetic disk, for captures
DISKMAP_MOCK ?= $(HOME)/Library/Application Support/Diskmap/mock-hdd.bin
MOCK ?= $(DISKMAP_MOCK)
diskmap-mock-export: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	./$(LUA_OBJC_BIN) --export-mock="$(MOCK)" apps/diskmap/init.lua

diskmap-mock: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	@test -f "$(MOCK)" || { echo "No snapshot at $(MOCK); run make diskmap-mock-export first" >&2; exit 1; }
	./$(LUA_OBJC_BIN) --mock-file="$(MOCK)" apps/diskmap/init.lua

diskmap-showcase: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	./$(LUA_OBJC_BIN) apps/diskmap/init.lua --showcase

TEST_FILES = $(wildcard tests/*.test.lua)

test: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS) $(PARITY_IMAGE_DIFF)
	@passed=0; failed=0; \
	for t in $(TEST_FILES); do \
		echo "--- $$t ---"; \
		if ./$(LUA_OBJC_BIN) --test $$t 2>&1; then \
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
LUA_SRC_DIR := vendor/lua-5.4.8/src
LUA_CORE := lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject \
	lopcodes lparser lstate lstring ltable ltm lundump lvm lzio
LUA_LIB := lauxlib lbaselib lcorolib ldblib liolib lmathlib loadlib loslib \
	lstrlib ltablib lutf8lib linit
LUA_OBJS := $(addprefix build/ios/lua/,$(addsuffix .o,$(LUA_CORE) $(LUA_LIB)))
IOS_LUA_A := build/ios/liblua.a
HOST_BUNDLE := build/ios/LuaRuntime.app
HOST_BINARY := $(HOST_BUNDLE)/LuaRuntime
PACKAGER := build/lua-objc-packager
IOS_HOST_SRCS := ios/LuaRuntime/main.m ios/LuaRuntime/LRTApplicationDelegate.m \
	ios/LuaRuntime/LRTSceneDelegate.m ios/LuaRuntime/LRTApplicationController.m \
	ios/LuaRuntime/LRTViewCapture.m \
	ios/LuaRuntime/LRTResourceLoader.m ios/LuaRuntime/LRTReloadConnection.m \
	ios/LuaRuntime/LRTErrorViewController.m
IOS_CFLAGS_C := -Wall -O2 -isysroot $(IOS_SDK) -arch arm64 \
	-mios-simulator-version-min=$(IOS_MIN) -DLUA_USE_IOS \
	-I$(LUA_SRC_DIR)
IOS_CFLAGS := -fobjc-arc $(IOS_CFLAGS_C) \
	-Iios/LuaRuntime -Isrc -Ibuild -I$(LIBGIT2_INCLUDE)
IOS_LIBGIT2_A := build/libgit2/iphonesimulator-arm64/libgit2.a

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

$(HOST_BINARY): $(IOS_LUA_A) $(IOS_HOST_SRCS) ios/LuaRuntime/LuaRuntime.h $(UIKIT_RUNTIME_SRC) \
		$(UIKIT_RUNTIME_FRAGMENTS) $(GENERATED_DIR)/UIKit.lua.h \
		ios/LuaRuntime/Info.plist ios/LuaRuntime/AppIcon.png src/plugins/git/Git.c src/plugins/speech/Speech.m $(IOS_LIBGIT2_A)
	@test -n "$(IOS_SDK)" || { echo "iPhone Simulator SDK missing; set DEVELOPER_DIR"; exit 1; }
	@echo "Building iOS host..."
	@mkdir -p $(HOST_BUNDLE)
	@$(IOS_CC) $(IOS_CFLAGS) \
		-framework UIKit -framework CoreText -framework Foundation -framework CoreGraphics -framework QuartzCore -framework Symbols -framework UserNotifications -framework Security -framework WebKit -framework SceneKit -framework GameController -framework AVFoundation -framework Speech \
		-o $(HOST_BUNDLE)/LuaRuntime \
		$(IOS_HOST_SRCS) $(UIKIT_RUNTIME_SRC) src/plugins/git/Git.c src/plugins/speech/Speech.m $(IOS_LUA_A) \
		$(IOS_LIBGIT2_A) $(LIBGIT2_LIBS)
	@cp ios/LuaRuntime/Info.plist $(HOST_BUNDLE)/Info.plist
	@cp ios/LuaRuntime/AppIcon.png $(HOST_BUNDLE)/AppIcon.png
	@printf 'APPL????' > $(HOST_BUNDLE)/PkgInfo
	@codesign --sign - --force --entitlements /dev/null $(HOST_BUNDLE) 2>/dev/null \
		|| codesign --sign - --force $(HOST_BUNDLE)

ios-host: $(HOST_BINARY)
ios-packager: $(PACKAGER)

ios-packager-run: ios-packager
	./$(PACKAGER) --root "$(CURDIR)" --port 8081 --entry "$(or $(PROJECT),demo/hello)"

ios-packager-stop:
	@if [ -f build/ios/packager.pid ]; then kill $$(cat build/ios/packager.pid) 2>/dev/null || true; rm -f build/ios/packager.pid; fi

ios-run: ios-host ios-packager
	chmod +x scripts/ios-run.sh
	DEVELOPER_DIR=$(DEVELOPER_DIR) DEVICE="$(DEVICE)" PROJECT="$(or $(PROJECT),demo/hello)" \
		scripts/ios-run.sh

ios-internal-screenshot: ios-host ios-packager
	DEVELOPER_DIR=$(DEVELOPER_DIR) OUT="$(or $(OUT),/tmp/ios-internal-screenshot.png)" \
		PROJECT="$(or $(PROJECT),demo/hello)" DEVICE="$(DEVICE)" \
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
	@rm -f $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) build/UIKit.dylib
	@rm -f build/appkit-runtime.o build/appkit-module.o
	@rm -f $(GENERATED_DIR)/AppKit.lua.h $(GENERATED_DIR)/UIKit.lua.h
	@rm -rf build/ios $(PACKAGER)

screenshot: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
	./$(LUA_OBJC_BIN) --screenshot=$(or $(OUT),/tmp/screenshot.png) $(ARGS)

DOC_SRC = lua/embedded/AppKit.lua lua/embedded/UIKit.lua lua/ui/meshgradient.lua lua/ui/lazy.lua lua/ui/webpage.lua lua/ui/shader.lua
DOC_OUT = docs/reference/generated

docs:
	python3 scripts/docs/generate.py --src $(DOC_SRC) --out $(DOC_OUT)
	python3 -m mkdocs build

docs-check:
	python3 scripts/docs/generate.py --src $(DOC_SRC) --check --strict

parity-check:
	python3 scripts/parity/validate_manifest.py

$(PARITY_IMAGE_DIFF): scripts/parity/image_diff.c
	mkdir -p $(dir $@)
	$(CC) -std=c11 -Wall -Wextra -O2 -fconstant-cfstrings \
		-framework CoreFoundation -framework CoreGraphics -framework ImageIO \
		-o $@ $<

parity-image-diff: $(PARITY_IMAGE_DIFF)

parity-visual:
	PLATFORM="$(or $(PLATFORM),macos)" DEVICE="$(or $(DEVICE),booted)" SPEC="$(SPEC)" \
		sh scripts/parity/run_visual.sh

parity-case: parity-check $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES)
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

.PHONY: all uikit run clean test docs docs-check parity-check parity-case parity-report parity-image-diff parity-visual run-hello run-list run-live run-weather run-welcome run-mail run-layout run-diskmap screenshot ios-host ios-packager ios-packager-run ios-run ios-internal-screenshot ios-screenshot ios ios-reset

# Standalone iPad development app (no Mac packager required).
.PHONY: ipad ipad-simulator ipad-run ipad-deploy list-devices
.PHONY: iphone-deploy
iphone-deploy:
	$(MAKE) ipad-deploy DEVICE_TYPE=iPhone APP="$(or $(APP),adventure-arena)" \
		DEVICE_FAMILY=1 FILE_SHARING=0

ipad:
	$(MAKE) -f scripts/ipad/build.mk SDK=iphoneos app
ipad-simulator:
	$(MAKE) -f scripts/ipad/build.mk SDK=iphonesimulator app
ipad-run:
	$(MAKE) -f scripts/ipad/build.mk SDK=iphonesimulator run
ipad-deploy:
	$(MAKE) -f scripts/ipad/build.mk SDK=iphoneos deploy
list-devices:
	xcrun devicectl list devices

.PHONY: diskmap-app diskmap-mock diskmap-mock-export diskmap-showcase
diskmap-app: diskmap-xcode-build

DISKMAP_XCODE_PROJECT = apps/diskmap/Diskmap.xcodeproj
DISKMAP_XCODE_DERIVED_DATA ?= build/xcode-derived
DISKMAP_XCODE_ROOT = $(abspath $(DISKMAP_XCODE_DERIVED_DATA))
DISKMAP_XCODE_CONFIGURATION ?= Release
.PHONY: diskmap-xcode-build
diskmap-xcode-build:
	xcodebuild -project $(DISKMAP_XCODE_PROJECT) \
		-scheme Diskmap -configuration $(DISKMAP_XCODE_CONFIGURATION) \
		-destination 'generic/platform=macOS' \
		-derivedDataPath $(DISKMAP_XCODE_ROOT) \
		SYMROOT="$(DISKMAP_XCODE_ROOT)/Products" \
		OBJROOT="$(DISKMAP_XCODE_ROOT)/Intermediates" \
		build

# Each app's platform and release channels live in scripts/release/apps.json.
# Releases use the Apple toolchain directly, without Xcode projects.
VERSION ?=
BUILD_NUMBER ?= 1
.PHONY: release release-build publish appstore-upload
RELEASE_FLAGS = --version "$(VERSION)" --build-number "$(BUILD_NUMBER)" $(if $(APP),--app "$(APP)")
release-build:
	python3 scripts/release/release.py build $(RELEASE_FLAGS)
release:
	python3 scripts/release/release.py release $(RELEASE_FLAGS) $(if $(filter 1,$(UNSIGNED)),--unsigned) \
		$(if $(filter 1,$(STORE)),--store --profile "$(PROFILE)")

publish:
	python3 scripts/release/release.py publish $(RELEASE_FLAGS)

appstore-upload:
	python3 scripts/release/release.py upload $(RELEASE_FLAGS)

APP ?=
TARGET ?=
.PHONY: xcode
xcode:
	@if [ "$(APP)" = diskmap ] && [ "$(TARGET)" = macos ]; then \
		open $(DISKMAP_XCODE_PROJECT); \
	elif [ "$(APP)" = dnb ] && [ "$(TARGET)" = macos ]; then \
		open apps/dnb/DrumAndBass.xcodeproj; \
	else \
		echo "usage: make xcode APP=diskmap|dnb TARGET=macos" >&2; exit 2; \
	fi

# Diskmap showreel (reels/diskmap, rendered with modules/reel): `make
# diskmap-reel` renders build/Diskmap-Showreel.mov, first capturing the pages
# when reels/diskmap/captures is empty (generated, not committed). Capturing
# runs reels/diskmap/capture.lua in one Diskmap launch, which opens its
# window; `make diskmap-reel-captures` recaptures after a UI change.
DISKMAP_CAPTURE = ./$(LUA_OBJC_BIN) --capture-plan=reels/diskmap/capture.lua --width=1280 --height=800 \
	apps/diskmap/init.lua --showcase
# Diskmap's tour screenshots (apps/diskmap/tour, committed JPEGs): captured
# from the showcase disk in light and dark and cropped to each page by the plan.
.PHONY: diskmap-tour-captures
diskmap-tour-captures: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	./$(LUA_OBJC_BIN) --capture-plan=apps/diskmap/tour/capture.lua --width=1100 --height=688 \
		apps/diskmap/init.lua --showcase

# Diskmap's Mac App Store screenshots (apps/diskmap/store-assets/en/screenshots,
# committed JPEGs): five promotional artboards with real showcase windows,
# exported at 2880 × 1800 without transparency. PYTHON must provide Pillow/NumPy.
DISKMAP_STORE_PYTHON ?= python3
.PHONY: diskmap-store-screenshots
diskmap-store-screenshots: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	mkdir -p build/diskmap-store
	./$(LUA_OBJC_BIN) --capture-plan=apps/diskmap/store-assets/capture.lua --width=1280 --height=640 \
		apps/diskmap/init.lua --showcase
	$(DISKMAP_STORE_PYTHON) scripts/diskmap-store-promos.py

.PHONY: diskmap-store-preview
diskmap-store-preview:
	@test -f build/Diskmap-Showreel.mov || (echo "Run make diskmap-reel first" >&2; exit 1)
	swift -module-cache-path build/diskmap-store/swift-cache scripts/diskmap-store-preview.swift

.PHONY: diskmap-reel diskmap-reel-captures
diskmap-reel: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	@ls reels/diskmap/captures/*.png >/dev/null 2>&1 || $(DISKMAP_CAPTURE)
	./$(LUA_OBJC_BIN) reels/diskmap/init.lua render build/Diskmap-Showreel.mov

diskmap-reel-captures: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	$(DISKMAP_CAPTURE)

# The lua-objc promo (reels/promo): `make promo-reel` renders
# build/videos/lua-objc-Promo.mov, first capturing the apps when
# reels/promo/captures is empty (generated, not committed). Capturing opens
# app windows and drives the iPhone and iPad Simulators headlessly (Xcode
# needed); `make promo-reel-captures` recaptures after an app changes.
.PHONY: promo-reel promo-reel-captures
promo-reel: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	@ls reels/promo/captures/*.png >/dev/null 2>&1 || ./$(LUA_OBJC_BIN) reels/promo/capture.lua
	@mkdir -p build/videos
	./$(LUA_OBJC_BIN) reels/promo/init.lua render build/videos/lua-objc-Promo.mov

promo-reel-captures: $(LUA_OBJC_BIN) $(FRAMEWORK_MODULES) $(NATIVE_PLUGINS)
	./$(LUA_OBJC_BIN) reels/promo/capture.lua

.PHONY: adventure-arena-tour-captures
adventure-arena-tour-captures: ios-host ios-packager
	sh apps/adventure-arena/tour/capture.sh
