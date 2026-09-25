-- Adventure Arena's Xcode project is checked in so Xcode Cloud can discover it.
-- Regenerate with: premake5 xcode4
workspace "AdventureArena"
	location "ios/AdventureArena"
	configurations { "Debug", "Release" }
	startproject "AdventureArena"

project "AdventureArena"
	location "ios/AdventureArena"
	kind "WindowedApp"
	language "C"
	system "ios"
	systemversion "26.5"
	architecture "ARM64"
	iosfamily "iPhone/iPod touch"
	files {
		"ios/AdventureArena/Info.plist",
		"ios/AdventureArena/Assets.xcassets",
		"ios/LuaRuntime/**.m",
		"ios/LuaRuntime/LuaRuntime.h",
		"src/uikit_module.m",
		"vendor/lua-5.4.8/src/**.c",
	}
	removefiles {
		"vendor/lua-5.4.8/src/lua.c",
		"vendor/lua-5.4.8/src/luac.c",
	}
	includedirs { "ios/LuaRuntime", "src", "build", "vendor/lua-5.4.8/src" }
	defines { "LUA_USE_IOS" }
	links {
		"UIKit.framework", "Foundation.framework", "CoreGraphics.framework",
		"QuartzCore.framework", "Security.framework", "WebKit.framework",
		"AVFoundation.framework", "Speech.framework",
	}
	xcodebuildresources { "ios/AdventureArena/Assets.xcassets" }
	xcodebuildsettings {
		PRODUCT_BUNDLE_IDENTIFIER = "org.luaobjc.adventure-arena",
		CODE_SIGN_STYLE = "Automatic",
		DEVELOPMENT_TEAM = "BM2R8F5YHC",
		CLANG_ENABLE_OBJC_ARC = "YES",
		GENERATE_INFOPLIST_FILE = "NO",
		INFOPLIST_FILE = "ios/AdventureArena/Info.plist",
		TARGETED_DEVICE_FAMILY = "1",
		ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon",
	}
	prebuildcommands {
		"cd \"$PROJECT_DIR/../..\" && mkdir -p build/generated && xxd -i -n UIKit_lua lua/embedded/UIKit.lua build/generated/UIKit.lua.h",
	}
	postbuildcommands {
		"cd \"$PROJECT_DIR/../..\" && python3 scripts/ipad/xcode_bundle.py --bundle \"$TARGET_BUILD_DIR/$WRAPPER_NAME\"",
	}

	filter "configurations:Debug"
		symbols "On"
	filter "configurations:Release"
		optimize "Speed"
		symbols "On"
