#!/bin/sh
# The Mac side of the tour's screenshots (`make adventure-arena-tour-captures`).
# Serves the capture harness (tour/init.lua) to the iPhone Simulator, then
# answers the requests of its plan (tour/capture.lua): set the appearance,
# or take a screenshot and crop it to the tour's image box.
#
# The crop offsets in the plan are points on DEVICE's screen, so the device
# is fixed. The simulator's own appearance is put back when the run ends,
# and the harness keeps its library in memory, so nothing saved is touched.
# Images are moved into the tour folder only once the run is over: the
# packager watches that folder, and a new file there would reload the app
# and start the plan again.
set -eu

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DEVICE="iPhone 17 Pro"
POINTS=402
PORT="${PORT:-8097}"
OUT="${OUT:-$ROOT/apps/adventure-arena/tour}"
QUALITY=90
HOST=org.luaobjc.host

UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == sys.argv[1]:
            print(device["udid"]); raise SystemExit
' "$DEVICE")"
[ -n "$UDID" ] || { echo "tour captures: no available simulator named $DEVICE" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$ROOT/build/ios/LuaRuntime.app"
APPEARANCE="$(xcrun simctl ui "$UDID" appearance)"
DIR="$(xcrun simctl get_app_container "$UDID" "$HOST" data)/tmp/adventure-arena-tour"
rm -rf "$DIR"
STAGE="$(mktemp -d)"
mkdir -p "$DIR" "$OUT"

"$ROOT/build/lua-objc-packager" --root "$ROOT" --port "$PORT" --entry apps/adventure-arena/tour >/dev/null 2>&1 &
PACKAGER=$!
cleanup() {
	kill "$PACKAGER" 2>/dev/null || true
	xcrun simctl terminate "$UDID" "$HOST" 2>/dev/null || true
	xcrun simctl ui "$UDID" appearance "$APPEARANCE" 2>/dev/null || true
	rm -rf "$DIR" "$STAGE"
}
trap cleanup EXIT
until curl -sf "http://127.0.0.1:$PORT/health" >/dev/null; do sleep 0.2; done
SIMCTL_CHILD_LUA_OBJC_PACKAGER="http://127.0.0.1:$PORT" \
	xcrun simctl launch --terminate-running-process "$UDID" "$HOST" >/dev/null

# shot <name> <top> <box width> <box height> <box scale>: one full-width band
# of the screen starting <top> points down, with the box's proportions,
# saved as <name>.jpg at <scale> times the box.
shot() {
	raw="$DIR/$1.png"
	xcrun simctl io "$UDID" screenshot "$raw" >/dev/null 2>&1
	width="$(sips -g pixelWidth "$raw" | awk '/pixelWidth/ { print $2 }')"
	height=$((width * $4 / $3))
	offset=$((width * $2 / POINTS))
	sips -c "$height" "$width" --cropOffset "$offset" 0 "$raw" >/dev/null
	sips -z $(($4 * $5)) $(($3 * $5)) -s format jpeg -s formatOptions "$QUALITY" "$raw" --out "$STAGE/$1.jpg" >/dev/null
}

idle=0
while :; do
	if [ ! -f "$DIR/request" ]; then
		sleep 0.1
		idle=$((idle + 1))
		[ "$idle" -lt 600 ] || { echo "tour captures: the app stopped asking for shots" >&2; exit 1; }
		continue
	fi
	idle=0
	read -r verb first top width height scale < "$DIR/request" || true
	case "$verb" in
		appearance) xcrun simctl ui "$UDID" appearance "$first" ;;
		shot) shot "$first" "$top" "$width" "$height" "$scale" ;;
		done) break ;;
		*) echo "tour captures: unknown request $verb" >&2; exit 1 ;;
	esac
	rm -f "$DIR/request"
done

kill "$PACKAGER" 2>/dev/null || true
wait "$PACKAGER" 2>/dev/null || true
for image in "$STAGE"/*.jpg; do
	mv "$image" "$OUT/"
	echo "tour captures: $(basename "$image")"
done
