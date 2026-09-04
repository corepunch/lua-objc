#!/bin/sh
# Open Apple's Simulator, install LuaObjCHost, stream Lua/assets from the packager.
set -e
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
DEVICE="${DEVICE:-iPhone 17}"
ENTRY="${PROJECT:-examples/hello}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIMAPP="$DEVELOPER_DIR/Applications/Simulator.app"
PACKAGER="$ROOT/build/lua-objc-packager"
HOST_BUNDLE="$ROOT/build/ios/LuaObjCHost.app"
PACKAGER_URL="http://127.0.0.1:8081"
LOGDIR="$ROOT/build/ios"
mkdir -p "$LOGDIR"

if [ ! -d "$SIMAPP" ]; then
	echo "ios-run: Apple Simulator not at $SIMAPP" >&2
	exit 1
fi
if [ ! -x "$PACKAGER" ]; then
	echo "ios-run: missing $PACKAGER (run make ios-packager)" >&2
	exit 1
fi
if [ ! -d "$HOST_BUNDLE" ]; then
	echo "ios-run: missing $HOST_BUNDLE (run make ios-host)" >&2
	exit 1
fi

ensure_packager() {
	if curl -sf "$PACKAGER_URL/health" >/dev/null; then
		echo "ios-run: packager already running at $PACKAGER_URL"
		return 0
	fi
	echo "ios-run: starting packager $PACKAGER_URL  entry=$ENTRY"
	"$PACKAGER" --root "$ROOT" --port 8081 --entry "$ENTRY" \
		>>"$LOGDIR/packager.log" 2>&1 &
	echo $! > "$LOGDIR/packager.pid"
	i=0
	while [ "$i" -lt 25 ]; do
		if curl -sf "$PACKAGER_URL/health" >/dev/null; then return 0; fi
		i=$((i + 1))
		sleep 0.2
	done
	echo "ios-run: packager failed to start" >&2
	cat "$LOGDIR/packager.log" >&2
	exit 1
}

ensure_packager
echo "ios-run: packager stays up after this command (make ios-packager-stop to kill it)"

echo "ios-run: boot $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b

UDID="$(xcrun simctl list devices booted -j | python3 -c '
import json,sys
d=json.load(sys.stdin)
for devs in d.get("devices",{}).values():
    for x in devs:
        if x.get("state")=="Booted" and "iPhone" in x.get("name",""):
            print(x["udid"]); raise SystemExit
')"
echo "ios-run: open $SIMAPP udid=$UDID"
open -a "$SIMAPP" --args -CurrentDeviceUDID "$UDID"
sleep 1

echo "ios-run: install $HOST_BUNDLE"
xcrun simctl install booted "$HOST_BUNDLE"

echo "ios-run: launch org.luaobjc.host  (UI is in Simulator.app, not this terminal)"
SIMCTL_CHILD_LUA_OBJC_APP="$ENTRY" \
SIMCTL_CHILD_LUA_OBJC_PACKAGER="$PACKAGER_URL" \
xcrun simctl launch --console --terminate-running-process booted org.luaobjc.host
