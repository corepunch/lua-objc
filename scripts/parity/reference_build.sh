#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
source="$repo_root/tests/parity/reference/ReferenceHost.swift"
output_dir=${REFERENCE_BUILD_DIR:-"$repo_root/build/parity/reference"}
app="$output_dir/SwiftUIParityReference.app"
output="$app/Contents/MacOS/SwiftUIParityReference"

if [ ! -f "$source" ]; then
	echo "reference build failed: missing $source" >&2
	exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
	export DEVELOPER_DIR
fi

if ! swiftc_path=$(xcrun --find swiftc 2>/dev/null); then
	echo "reference build blocked: full Xcode is required; set DEVELOPER_DIR to an Xcode developer directory" >&2
	exit 2
fi

if ! sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null); then
	echo "reference build blocked: macOS SDK unavailable from the active Xcode" >&2
	exit 2
fi

mkdir -p "$output_dir"
mkdir -p "$app/Contents/MacOS"
module_cache=${SWIFT_MODULECACHE_PATH:-/tmp/lua-objc-swift-module-cache}
mkdir -p "$module_cache"
export SWIFT_MODULECACHE_PATH="$module_cache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$module_cache}"
"$swiftc_path" \
	-sdk "$sdk" \
	-target arm64-apple-macos26.0 \
	-parse-as-library \
	-framework AppKit \
	-framework SwiftUI \
	-o "$output" \
	"$source"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>SwiftUIParityReference</string>
	<key>CFBundleIdentifier</key>
	<string>org.luaobjc.parity.reference</string>
	<key>CFBundleName</key>
	<string>SwiftUI Parity Reference</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
</dict>
</plist>
PLIST

# The executable is linker-signed before the generated Info.plist exists.
# Re-sign the completed bundle so LaunchServices binds the executable and
# metadata as one runnable application.
codesign --force --deep --sign - "$app" >/dev/null

echo "reference host built: $app"
