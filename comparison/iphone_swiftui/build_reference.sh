#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/comparison/iphone_swiftui/reference/ComparisonHost.swift"
BUILD="$ROOT/build/comparison/iphone_swiftui"
APP="$BUILD/SwiftUIComparison.app"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
MODULE_CACHE="${SWIFT_MODULECACHE_PATH:-/tmp/lua-objc-iphone-comparison-module-cache}"
mkdir -p "$MODULE_CACHE"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$MODULE_CACHE}"
mkdir -p "$APP"
"$SWIFTC" \
	-sdk "$SDK" \
	-target arm64-apple-ios26.5-simulator \
	-parse-as-library \
	-framework UIKit \
	-framework SwiftUI \
	-o "$APP/SwiftUIComparison" \
	"$SOURCE"
cp "$ROOT/comparison/iphone_swiftui/contract.json" "$APP/contract.json"
plist() { /usr/libexec/PlistBuddy "$@" >/dev/null; }
plist -c "Clear dict" "$APP/Info.plist" 2>/dev/null || true
plist -c "Add :CFBundleExecutable string SwiftUIComparison" "$APP/Info.plist"
plist -c "Add :CFBundleIdentifier string org.luaobjc.comparison.swiftui" "$APP/Info.plist"
plist -c "Add :CFBundleName string SwiftUIComparison" "$APP/Info.plist"
plist -c "Add :CFBundlePackageType string APPL" "$APP/Info.plist"
plist -c "Add :CFBundleShortVersionString string 1" "$APP/Info.plist"
plist -c "Add :CFBundleVersion string 1" "$APP/Info.plist"
plist -c "Add :MinimumOSVersion string 26.5" "$APP/Info.plist"
plist -c "Add :UIStatusBarHidden bool false" "$APP/Info.plist"
plist -c "Add :UIDeviceFamily array" "$APP/Info.plist"
plist -c "Add :UIDeviceFamily:0 integer 1" "$APP/Info.plist"
plist -c "Add :UIApplicationSceneManifest dict" "$APP/Info.plist"
plist -c "Add :UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool false" "$APP/Info.plist"
plist -c "Add :UILaunchScreen dict" "$APP/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
