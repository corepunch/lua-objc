#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DEVICE="${DEVICE:-iPhone 17}"
FIXTURES="${1:-all}"
export DEVELOPER_DIR

case "$FIXTURES" in
	all) set -- labels buttons stacks controls ;;
	labels|buttons|stacks|controls) set -- "$FIXTURES" ;;
	*) echo "usage: capture.sh [all|labels|buttons|stacks|controls]" >&2; exit 2 ;;
esac

APP="$("$ROOT/comparison/iphone_swiftui/build_reference.sh")"
REFERENCE_ID="org.luaobjc.comparison.swiftui"
LUA_ID="org.luaobjc.host"
PACKAGER_PORT="${PACKAGER_PORT:-18082}"
PACKAGER_URL="http://127.0.0.1:$PACKAGER_PORT"
CAPTURE_TMP="$ROOT/build/comparison/iphone_swiftui/captures/ios-26.5-iphone-17"
OUTPUT="$ROOT/comparison/iphone_swiftui/captures/ios-26.5-iphone-17"
mkdir -p "$CAPTURE_TMP"

make -C "$ROOT" ios-host ios-packager
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl ui "$DEVICE" appearance light
xcrun simctl ui "$DEVICE" content_size large
xcrun simctl ui "$DEVICE" increase_contrast disabled
xcrun simctl status_bar "$DEVICE" override \
	--time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
	--cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl install "$DEVICE" "$ROOT/build/ios/LuaRuntime.app"

if curl -sf "$PACKAGER_URL/health" >/dev/null; then
	echo "capture.sh: port $PACKAGER_PORT already serves a packager; choose PACKAGER_PORT" >&2
	exit 1
fi
"$ROOT/build/lua-objc-packager" --root "$ROOT" \
	--entry comparison/iphone_swiftui --port "$PACKAGER_PORT" \
	>>"$ROOT/build/comparison/iphone_swiftui/packager.log" 2>&1 &
PACKAGER_PID=$!
cleanup() {
	kill "$PACKAGER_PID" 2>/dev/null || true
	wait "$PACKAGER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
packager_ready=0
for _ in $(seq 1 100); do
	if ! kill -0 "$PACKAGER_PID" 2>/dev/null; then
		cat "$ROOT/build/comparison/iphone_swiftui/packager.log" >&2
		exit 1
	fi
	if curl -sf "$PACKAGER_URL/health" >/dev/null; then
		packager_ready=1
		break
	fi
	sleep 0.1
done
if [ "$packager_ready" -ne 1 ]; then
	cat "$ROOT/build/comparison/iphone_swiftui/packager.log" >&2
	exit 1
fi

for fixture in "$@"; do
	rm -f "$CAPTURE_TMP/swiftui-$fixture.png" "$CAPTURE_TMP/lua-objc-$fixture.png"
	xcrun simctl launch --terminate-running-process "$DEVICE" com.apple.springboard >/dev/null
	sleep 0.5
	SIMCTL_CHILD_SWIFTUI_COMPARISON_FIXTURE="$fixture" \
		xcrun simctl launch --terminate-running-process "$DEVICE" "$REFERENCE_ID"
	sleep 2
	xcrun simctl io "$DEVICE" screenshot "$CAPTURE_TMP/swiftui-$fixture.png"
	xcrun simctl launch --terminate-running-process "$DEVICE" com.apple.springboard >/dev/null
	sleep 0.5
	SIMCTL_CHILD_LUA_OBJC_APP=comparison/iphone_swiftui \
	SIMCTL_CHILD_LUA_OBJC_PACKAGER="$PACKAGER_URL" \
	SIMCTL_CHILD_LUA_OBJC_COMPARISON_FIXTURE="$fixture" \
		xcrun simctl launch --terminate-running-process "$DEVICE" "$LUA_ID"
	sleep 2
	xcrun simctl io "$DEVICE" screenshot "$CAPTURE_TMP/lua-objc-$fixture.png"
done

cleanup
trap - EXIT INT TERM
mkdir -p "$OUTPUT"
for fixture in "$@"; do
	cp "$CAPTURE_TMP/swiftui-$fixture.png" "$OUTPUT/"
	cp "$CAPTURE_TMP/lua-objc-$fixture.png" "$OUTPUT/"
done

python3 - "$ROOT" "$DEVICE" "$OUTPUT" <<'PY'
import json, pathlib, subprocess, sys
root, device, output = map(pathlib.Path, sys.argv[1:])
device_name = str(device)
devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
runtime_id, selected = next((identifier, item)
    for identifier, group in devices["devices"].items() for item in group
    if item["name"] == device_name)
simulator = subprocess.check_output(
    ["xcrun", "simctl", "list", "runtimes", "-j"], text=True)
runtimes = json.loads(simulator)["runtimes"]
runtime = next((item for item in runtimes if item["identifier"] == runtime_id), {})
xcode = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
capture = {
    "device": selected["name"],
    "udid": selected["udid"],
    "runtime": runtime.get("version", runtime_id),
    "runtimeBuild": runtime.get("buildversion"),
    "xcode": xcode,
    "appearance": "light",
    "increaseContrast": "disabled",
    "locale": "en_US",
    "layoutDirection": "leftToRight",
    "dynamicType": "large",
    "statusBarTime": "9:41",
    "screenshots": sorted(path.name for path in output.glob("*.png")),
}
(output / "capture.json").write_text(json.dumps(capture, indent=2) + "\n")
PY

echo "iPhone comparison captures written to $OUTPUT"
