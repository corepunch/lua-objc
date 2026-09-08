#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
source="$repo_root/tests/parity/batch/BatchReferenceHost.swift"
output_dir=${BATCH_REFERENCE_BUILD_DIR:-"$repo_root/build/parity/batch"}
mode=${1:---macos}

if [ ! -f "$source" ]; then
	echo "batch reference build failed: missing $source" >&2
	exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
	export DEVELOPER_DIR
fi

if ! swiftc_path=$(xcrun --find swiftc 2>/dev/null); then
	echo "batch reference build blocked: full Xcode is required; set DEVELOPER_DIR to an Xcode developer directory" >&2
	exit 2
fi

mkdir -p "$output_dir"
module_cache=${SWIFT_MODULECACHE_PATH:-/tmp/lua-objc-batch-swift-module-cache}
mkdir -p "$module_cache"
export SWIFT_MODULECACHE_PATH="$module_cache"
export CLANG_MODULE_CACHE_PATH=${CLANG_MODULE_CACHE_PATH:-"$module_cache"}

case "$mode" in
	--macos)
		if ! sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null); then
			echo "batch reference build blocked: macOS SDK unavailable from the active Xcode" >&2
			exit 2
		fi
		output="$output_dir/SwiftUIBatchReference"
		"$swiftc_path" \
			-sdk "$sdk" \
			-target arm64-apple-macos26.0 \
			-parse-as-library \
			-framework AppKit \
			-framework SwiftUI \
			-o "$output" \
			"$source"
		;;
	--ios)
		if ! sdk=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null); then
			echo "batch reference build blocked: iPhone Simulator SDK unavailable from the active Xcode" >&2
			exit 2
		fi
		app="$output_dir/SwiftUIBatchReference-iOS.app"
		output="$app/SwiftUIBatchReference-iOS"
		mkdir -p "$app"
		"$swiftc_path" \
			-sdk "$sdk" \
			-target arm64-apple-ios26.0-simulator \
			-parse-as-library \
			-framework UIKit \
			-framework SwiftUI \
			-o "$output" \
			"$source"
		/usr/libexec/PlistBuddy -c "Clear dict" "$app/Info.plist" 2>/dev/null || true
		/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string SwiftUIBatchReference-iOS" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string org.luaobjc.parity.batch-reference" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :CFBundleName string SwiftUIBatchReference" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string 26.0" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily array" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily:0 integer 1" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :UIApplicationSceneManifest dict" "$app/Info.plist"
		/usr/libexec/PlistBuddy -c "Add :UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool false" "$app/Info.plist"
		codesign --force --sign - "$app"
		;;
	*)
		echo "usage: scripts/parity/batch_reference_build.sh [--macos|--ios]" >&2
		exit 2
		;;
esac

echo "SwiftUI batch reference host built: $output"
