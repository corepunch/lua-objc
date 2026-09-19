.DEFAULT_GOAL := app
.DELETE_ON_ERROR:
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
SDK ?= iphoneos
ARCH ?= arm64
IOS_MIN ?= 26.5
BUNDLE_ID ?= org.luaobjc.studio
TEAM ?=
PROFILE ?=
IPAD_DEVICE ?=
SDK_PATH := $(shell xcrun --sdk $(SDK) --show-sdk-path)
ROOT := build/ipad/$(SDK)-$(ARCH)
BUNDLE := $(ROOT)/LuaStudio.app
LUA := vendor/lua-5.4.8/src
LUA_SOURCES := $(filter-out $(LUA)/lua.c $(LUA)/luac.c,$(wildcard $(LUA)/*.c))
OBJECTS := $(patsubst $(LUA)/%.c,$(ROOT)/lua/%.o,$(LUA_SOURCES))
MIN_FLAG := $(if $(filter iphoneos,$(SDK)),-miphoneos-version-min,-mios-simulator-version-min)=$(IOS_MIN)
FLAGS := -isysroot $(SDK_PATH) -arch $(ARCH) $(MIN_FLAG) -O2 -Wall -DLUA_USE_IOS -I$(LUA)
HOST := $(wildcard ios/LuaRuntime/*.m)
FRAGMENTS := $(shell find src/uikit src/shared -name '*.m')
FRAMEWORKS := -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework Security
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
$(ROOT)/LuaStudio: $(OBJECTS) $(HOST) ios/LuaRuntime/LuaRuntime.h src/uikit_module.m $(FRAGMENTS) build/generated/UIKit.lua.h scripts/ipad/build.mk $(SIM_ENTITLEMENTS) $(SIM_DER)
	xcrun --sdk $(SDK) clang $(FLAGS) -fobjc-arc -Iios/LuaRuntime -Isrc -Ibuild $(HOST) src/uikit_module.m $(OBJECTS) $(FRAMEWORKS) $(SIM_LINK_FLAGS) -o $@
app: $(ROOT)/LuaStudio
	python3 scripts/ipad/bundle.py --binary $< --bundle $(BUNDLE) --sdk $(SDK) --identifier $(BUNDLE_ID) --minimum $(IOS_MIN)
ifeq ($(SDK),iphonesimulator)
	codesign --force --sign - $(BUNDLE)
endif
run: app
	python3 scripts/ipad/deploy.py --simulator --bundle $(BUNDLE) $(if $(IPAD_DEVICE),--device "$(IPAD_DEVICE)")
deploy: app
	@test "$(SDK)" = iphoneos || { echo 'Deploy requires SDK=iphoneos'; exit 1; }
	python3 scripts/ipad/deploy.py --bundle $(BUNDLE) $(if $(IPAD_DEVICE),--device "$(IPAD_DEVICE)") $(if $(TEAM),--team "$(TEAM)") $(if $(PROFILE),--profile "$(PROFILE)")
