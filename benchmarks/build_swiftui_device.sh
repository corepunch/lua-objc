#!/bin/bash
set -euo pipefail

bench_root=build/benchmarks/ios
bench_bundle="$bench_root/SwiftUIBenchmark.app"
bench_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p "$bench_bundle" "$bench_root/cache"
xcrun --sdk iphoneos swiftc -O -parse-as-library \
	-target arm64-apple-ios26.5 -sdk "$bench_sdk" \
	-module-cache-path "$bench_root/cache" \
	benchmarks/swiftui_device.swift -o "$bench_bundle/SwiftUIBenchmark"
python3 - "$bench_bundle/Info.plist" <<'PY'
import plistlib
from pathlib import Path
import sys

info = {
    'CFBundleDevelopmentRegion': 'en',
    'CFBundleExecutable': 'SwiftUIBenchmark',
    'CFBundleIdentifier': 'org.luaobjc.swiftui-benchmark',
    'CFBundleInfoDictionaryVersion': '6.0',
    'CFBundleName': 'SwiftUI Benchmark',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '1.0',
    'CFBundleSupportedPlatforms': ['iPhoneOS'],
    'CFBundleVersion': '1',
    'CADisableMinimumFrameDurationOnPhone': True,
    'LSRequiresIPhoneOS': True,
    'MinimumOSVersion': '26.5',
    'UIApplicationSceneManifest': {
        'UIApplicationSupportsMultipleScenes': False,
        'UISceneConfigurations': {
            'UIWindowSceneSessionRoleApplication': [{
                'UISceneConfigurationName': 'Default Configuration',
                'UISceneDelegateClassName': 'BenchmarkSceneDelegate',
            }],
        },
    },
    'UIDeviceFamily': [1],
    'UILaunchScreen': {},
    'UIRequiredDeviceCapabilities': ['arm64'],
    'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
}
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
printf '%s\n' "$bench_bundle"
