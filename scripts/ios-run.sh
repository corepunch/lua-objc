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
PIDFILE="$LOGDIR/packager.pid"
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
		running_entry="$(curl -sf "$PACKAGER_URL/entry" | python3 -c '
import json, sys
print(json.load(sys.stdin).get("path", ""))
')"
		expected_entry="$ENTRY"
		case "$expected_entry" in
			*.lua) ;;
			*) expected_entry="${expected_entry%/}/init.lua" ;;
		esac
		if [ "$running_entry" = "$expected_entry" ]; then
			echo "ios-run: packager already running at $PACKAGER_URL  entry=$running_entry"
			return 0
		fi

		echo "ios-run: switching packager entry $running_entry -> $expected_entry"
		packager_pid=""
		if [ -f "$PIDFILE" ]; then
			packager_pid="$(sed -n '1p' "$PIDFILE")"
		fi
		if [ -z "$packager_pid" ] || ! kill -0 "$packager_pid" 2>/dev/null; then
			packager_pid="$(lsof -tiTCP:8081 -sTCP:LISTEN | sed -n '1p')"
		fi
		if [ -z "$packager_pid" ] || ! ps -p "$packager_pid" -o command= | grep -q "$PACKAGER"; then
			echo "ios-run: port 8081 is owned by an unknown process; stop it manually" >&2
			exit 1
		fi
		kill "$packager_pid"
		i=0
		while curl -sf "$PACKAGER_URL/health" >/dev/null; do
			i=$((i + 1))
			if [ "$i" -ge 25 ]; then
				echo "ios-run: old packager did not stop" >&2
				exit 1
			fi
			sleep 0.2
		done
		rm -f "$PIDFILE"
	fi
	echo "ios-run: starting packager $PACKAGER_URL  entry=$ENTRY"
	"$PACKAGER" --root "$ROOT" --port 8081 --entry "$ENTRY" \
		>>"$LOGDIR/packager.log" 2>&1 &
	echo $! > "$PIDFILE"
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

# bootstatus -b blocks until boot completes.  First boot after an Xcode
# upgrade or `simctl erase` runs data migration that can take minutes.
BOOT_TIMEOUT=90
xcrun simctl bootstatus "$DEVICE" -b &
BOOT_PID=$!
i=0
while kill -0 "$BOOT_PID" 2>/dev/null; do
  sleep 1
  i=$((i + 1))
  if [ "$i" -ge "$BOOT_TIMEOUT" ]; then
    echo "" >&2
    echo "ios-run: simulator boot is slow (first boot after upgrade/erase takes minutes)." >&2
    echo "ios-run: the simulator IS booting — you should see the Apple logo in Simulator.app." >&2
    echo "ios-run: if stuck, try:  make ios-reset  then retry." >&2
    echo "" >&2
    kill "$BOOT_PID" 2>/dev/null || true
    wait "$BOOT_PID" 2>/dev/null || true
    break
  fi
done
wait "$BOOT_PID" 2>/dev/null || true

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

echo "ios-run: launch Impulse  (UI is in Simulator.app, not this terminal)"
if [ "${LUA_OBJC_RUN_NONBLOCKING:-0}" = "1" ]; then
	SIMCTL_CHILD_LUA_OBJC_APP="$ENTRY" \
	SIMCTL_CHILD_LUA_OBJC_PACKAGER="$PACKAGER_URL" \
		xcrun simctl launch --terminate-running-process booted org.luaobjc.host
else
	SIMCTL_CHILD_LUA_OBJC_APP="$ENTRY" \
	SIMCTL_CHILD_LUA_OBJC_PACKAGER="$PACKAGER_URL" \
		xcrun simctl launch --console --terminate-running-process booted org.luaobjc.host
fi
