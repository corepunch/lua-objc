.DEFAULT_GOAL := app
.DELETE_ON_ERROR:
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
SDK ?= iphoneos
ARCH ?= arm64
IOS_MIN ?= 26.5
APP ?= studio
APP_DIR := apps/$(APP)
BUNDLE_ID ?= $(if $(filter studio,$(APP)),org.luaobjc.studio,org.luaobjc.$(APP))
TEAM ?=
PROFILE ?=
IPAD_DEVICE ?=
DEVICE_TYPE ?= iPad
APP_ENTRY ?= $(APP_DIR)/init.lua
APP_DISPLAY_NAME ?= $(if $(filter studio,$(APP)),Lua Studio,$(if $(filter adventure-arena,$(APP)),Adventure Arena,$(APP)))
APP_BUNDLE ?= $(if $(filter studio,$(APP)),LuaStudio,$(APP))
DEVICE_FAMILY ?= 2
FILE_SHARING ?= 1
DEPLOY_DEVICE := $(IPAD_DEVICE)
SDK_PATH := $(shell xcrun --sdk $(SDK) --show-sdk-path)
ROOT := build/ipad/$(SDK)-$(ARCH)
BUNDLE := $(ROOT)/$(APP_BUNDLE).app
LUA := vendor/lua-5.4.8/src
LUA_SOURCES := $(filter-out $(LUA)/lua.c $(LUA)/luac.c,$(wildcard $(LUA)/*.c))
OBJECTS := $(patsubst $(LUA)/%.c,$(ROOT)/lua/%.o,$(LUA_SOURCES))
MIN_FLAG := $(if $(filter iphoneos,$(SDK)),-miphoneos-version-min,-mios-simulator-version-min)=$(IOS_MIN)
FLAGS := -isysroot $(SDK_PATH) -arch $(ARCH) $(MIN_FLAG) -O2 -g -Wall -DLUA_USE_IOS -I$(LUA)
HOST := $(wildcard ios/LuaRuntime/*.m)
FRAGMENTS := $(shell find src/uikit src/shared -name '*.m')
NATIVE_SOURCES := $(HOST) src/uikit_module.m src/plugins/git/Git.c src/plugins/speech/Speech.m
NATIVE_OBJECTS := $(addprefix $(ROOT)/native/,$(addsuffix .o,$(basename $(NATIVE_SOURCES))))
# libgit2 for the Git module, which the host preloads (src/plugins/git).
LIBGIT2 := build/libgit2/$(SDK)-$(ARCH)/libgit2.a
$(LIBGIT2): scripts/libgit2/libgit2.mk scripts/libgit2/git2_features.h scripts/libgit2/pcre2_config.h
	$(MAKE) -j$(shell getconf _NPROCESSORS_ONLN) -f scripts/libgit2/libgit2.mk SDK=$(SDK) ARCH=$(ARCH) OUT=$(@D)
FRAMEWORKS := -lz -framework UIKit -framework Foundation -framework CoreGraphics \
	-framework CoreText \
	-framework QuartzCore -framework Symbols -framework UserNotifications -framework Security -framework WebKit -framework SceneKit -framework GameController \
	-framework AVFoundation -framework Speech
ifeq ($(SDK),iphonesimulator)
SIM_ENTITLEMENTS := $(ROOT)/$(BUNDLE_ID).entitlements.plist
SIM_DER := $(SIM_ENTITLEMENTS:.plist=.der)
SIM_LINK_FLAGS := -Wl,-sectcreate,__TEXT,__entitlements,$(SIM_ENTITLEMENTS) -Wl,-sectcreate,__TEXT,__ents_der,$(SIM_DER)
$(SIM_ENTITLEMENTS): scripts/ipad/simulator_entitlements.py
	@mkdir -p $(@D)
	python3 $< --identifier $(BUNDLE_ID) --out $@
$(SIM_DER): $(SIM_ENTITLEMENTS)
	derq query -f xml -i $< -o $@
endif
ifeq ($(filter $(SDK),iphoneos iphonesimulator),)
$(error SDK must be iphoneos or iphonesimulator)
endif
.PHONY: app deploy run
$(ROOT)/lua/%.o: $(LUA)/%.c scripts/ipad/build.mk
	@mkdir -p $(@D)
	@xcrun --sdk $(SDK) clang $(FLAGS) -c $< -o $@
build/generated/UIKit.lua.h: lua/embedded/UIKit.lua
	@mkdir -p $(@D)
	xxd -i -n UIKit_lua $< $@
$(ROOT)/native/%.o: %.m ios/LuaRuntime/LuaRuntime.h $(FRAGMENTS) build/generated/UIKit.lua.h scripts/ipad/build.mk
	@mkdir -p $(@D)
	xcrun --sdk $(SDK) clang $(FLAGS) -fobjc-arc -Iios/LuaRuntime -Isrc -Ibuild -Ivendor/libgit2/include -c $< -o $@
$(ROOT)/native/%.o: %.c scripts/ipad/build.mk
	@mkdir -p $(@D)
	xcrun --sdk $(SDK) clang $(FLAGS) -Ivendor/libgit2/include -c $< -o $@
$(ROOT)/LuaStudio: $(OBJECTS) $(NATIVE_OBJECTS) $(LIBGIT2) scripts/ipad/build.mk $(SIM_ENTITLEMENTS) $(SIM_DER)
	xcrun --sdk $(SDK) clang $(FLAGS) $(NATIVE_OBJECTS) $(OBJECTS) $(LIBGIT2) $(FRAMEWORKS) $(SIM_LINK_FLAGS) -o $@
app: $(ROOT)/LuaStudio
	python3 scripts/ipad/bundle.py --binary $< --bundle $(BUNDLE) --sdk $(SDK) \
		--identifier $(BUNDLE_ID) --minimum $(IOS_MIN) --app "$(APP_DIR)" \
		--entry "$(APP_ENTRY)" --display-name "$(APP_DISPLAY_NAME)" \
		--device-family $(DEVICE_FAMILY) $(if $(filter 1,$(FILE_SHARING)),--file-sharing) \
		$(foreach overlay,$(OVERLAY),--overlay $(overlay))
ifeq ($(SDK),iphonesimulator)
	codesign --force --sign - $(BUNDLE)
endif
run: app
	python3 scripts/ipad/deploy.py --simulator --device-type "$(DEVICE_TYPE)" --bundle $(BUNDLE) $(if $(DEPLOY_DEVICE),--device "$(DEPLOY_DEVICE)")
deploy: app
	@test "$(SDK)" = iphoneos || { echo 'Deploy requires SDK=iphoneos'; exit 1; }
	python3 scripts/ipad/deploy.py --device-type "$(DEVICE_TYPE)" --bundle $(BUNDLE) $(if $(DEPLOY_DEVICE),--device "$(DEPLOY_DEVICE)") $(if $(TEAM),--team "$(TEAM)") $(if $(PROFILE),--profile "$(PROFILE)")
