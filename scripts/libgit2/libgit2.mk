# Build the pinned libgit2 source tree for one Apple SDK and architecture.
# Invoked by the root Makefile; can also be run directly with SDK, ARCH and OUT.
.DEFAULT_GOAL := all

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
SOURCE := $(ROOT)/vendor/libgit2
OUT ?= $(ROOT)/build/libgit2/$(SDK)-$(ARCH)
SDK ?= macosx
ARCH ?= arm64

ifeq ($(filter $(SDK),macosx iphoneos iphonesimulator),)
$(error unsupported libgit2 SDK '$(SDK)')
endif

CC := $(shell xcrun --sdk $(SDK) --find clang)
AR := $(shell xcrun --sdk $(SDK) --find ar)
SYSROOT := $(shell xcrun --sdk $(SDK) --show-sdk-path)
ifeq ($(SDK),macosx)
MIN_VERSION := -mmacosx-version-min=26.0
ICONV_DEFINE := -DGIT2_USE_ICONV
else ifeq ($(SDK),iphoneos)
MIN_VERSION := -miphoneos-version-min=26.5
ICONV_DEFINE :=
else
MIN_VERSION := -mios-simulator-version-min=26.5
ICONV_DEFINE :=
endif

BUILD := $(OUT)/make
INCLUDES := \
	-I$(BUILD)/include/pcre2 \
	-I$(SOURCE)/include \
	-I$(SOURCE)/src/libgit2 \
	-I$(SOURCE)/src/util \
	-I$(SOURCE)/deps/llhttp \
	-I$(SOURCE)/deps/pcre2 \
	-I$(SOURCE)/deps/xdiff \
	-I$(BUILD)/include

COMMON_CFLAGS := -O3 -DNDEBUG -std=c90 -arch $(ARCH) -isysroot $(SYSROOT) $(MIN_VERSION) \
	-D_GNU_SOURCE -fvisibility=hidden -Wno-deprecated -DPCRE2_STATIC \
	-DPCRE2_EXPORT= -DPCRE2_EXP_DECL= -DPCRE2_EXP_DEFN= $(INCLUDES)
PCRE2_CFLAGS := -DHAVE_CONFIG_H -DPCRE2_CODE_UNIT_WIDTH=8
SHA1DC_CFLAGS := -DSHA1DC_NO_STANDARD_INCLUDES=1 \
	-DSHA1DC_CUSTOM_INCLUDE_SHA1_C=\"git2_util.h\" \
	-DSHA1DC_CUSTOM_INCLUDE_UBC_CHECK_C=\"git2_util.h\"

PCRE2_SOURCES := $(addprefix $(SOURCE)/deps/pcre2/, \
	pcre2_auto_possess.c pcre2_chartables.c pcre2_chkdint.c \
	pcre2_compile.c pcre2_compile_cgroup.c pcre2_compile_class.c \
	pcre2_config.c pcre2_context.c pcre2_convert.c pcre2_dfa_match.c \
	pcre2_error.c pcre2_extuni.c pcre2_find_bracket.c pcre2_maketables.c \
	pcre2_match.c pcre2_match_data.c pcre2_match_next.c pcre2_newline.c \
	pcre2_ord2utf.c pcre2_pattern_info.c pcre2_script_run.c \
	pcre2_serialize.c pcre2_string_utils.c pcre2_study.c \
	pcre2_substitute.c pcre2_substring.c pcre2_tables.c pcre2_ucd.c \
	pcre2_valid_utf.c pcre2_xclass.c)

LIBGIT2_SOURCES := \
	$(wildcard $(SOURCE)/src/libgit2/*.c) \
	$(wildcard $(SOURCE)/src/libgit2/streams/*.c) \
	$(wildcard $(SOURCE)/src/libgit2/transports/*.c) \
	$(wildcard $(SOURCE)/src/util/*.c) \
	$(wildcard $(SOURCE)/src/util/allocators/*.c) \
	$(wildcard $(SOURCE)/src/util/unix/*.c) \
	$(SOURCE)/src/util/hash/collisiondetect.c \
	$(wildcard $(SOURCE)/src/util/hash/sha1dc/*.c) \
	$(SOURCE)/src/util/hash/common_crypto.c \
	$(SOURCE)/deps/llhttp/api.c \
	$(SOURCE)/deps/llhttp/http.c \
	$(SOURCE)/deps/llhttp/llhttp.c \
	$(wildcard $(SOURCE)/deps/xdiff/*.c) \
	$(PCRE2_SOURCES)

OBJECTS := $(patsubst $(SOURCE)/%.c,$(BUILD)/obj/%.o,$(LIBGIT2_SOURCES))
DEPS := $(OBJECTS:.o=.d)

.PHONY: all clean
all: $(OUT)/libgit2.a

$(BUILD)/include/git2_features.h: $(ROOT)/scripts/libgit2/git2_features.h | $(BUILD)/include
	cp $< $@

$(BUILD)/include/pcre2/config.h: $(ROOT)/scripts/libgit2/pcre2_config.h | $(BUILD)/include/pcre2
	cp $< $@

$(BUILD)/include $(BUILD)/include/pcre2:
	mkdir -p $@

$(BUILD)/obj/deps/pcre2/%.o: $(SOURCE)/deps/pcre2/%.c $(BUILD)/include/git2_features.h $(BUILD)/include/pcre2/config.h
	mkdir -p $(dir $@)
	$(CC) $(COMMON_CFLAGS) $(PCRE2_CFLAGS) -MMD -MP -MF $(@:.o=.d) -MT $@ -c $< -o $@

$(BUILD)/obj/src/util/hash/collisiondetect.o: $(SOURCE)/src/util/hash/collisiondetect.c $(BUILD)/include/git2_features.h $(BUILD)/include/pcre2/config.h
	mkdir -p $(dir $@)
	$(CC) $(COMMON_CFLAGS) $(SHA1DC_CFLAGS) $(ICONV_DEFINE) -MMD -MP -MF $(@:.o=.d) -MT $@ -c $< -o $@

$(BUILD)/obj/%.o: $(SOURCE)/%.c $(BUILD)/include/git2_features.h $(BUILD)/include/pcre2/config.h
	mkdir -p $(dir $@)
	$(CC) $(COMMON_CFLAGS) $(ICONV_DEFINE) -MMD -MP -MF $(@:.o=.d) -MT $@ -c $< -o $@

$(OUT)/libgit2.a: $(OBJECTS)
	mkdir -p $(OUT)
	rm -f $@
	$(AR) rcs $@ $(OBJECTS)

clean:
	rm -rf $(BUILD) $(OUT)/libgit2.a

-include $(DEPS)
