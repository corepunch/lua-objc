#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_PATH=${OUT:-/tmp/ios-internal-screenshot.png}
CAPTURE_PATH="parity/internal-screenshot.png"

mkdir -p "$(dirname "$OUT_PATH")"
rm -f "$OUT_PATH"

SIMCTL_CHILD_LUA_OBJC_INTERNAL_SCREENSHOT="$CAPTURE_PATH" \
	PROJECT="${PROJECT:-examples/hello}" \
	DEVICE="${DEVICE:-iPhone 17}" \
	"$ROOT/scripts/ios-run.sh"

data_container="$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
	xcrun simctl get_app_container booted org.luaobjc.host data)"
source_path="$data_container/tmp/$CAPTURE_PATH"

i=0
while [ ! -s "$source_path" ] && [ "$i" -lt 30 ]; do
	i=$((i + 1))
	sleep 0.2
done

if [ ! -s "$source_path" ]; then
	echo "ios internal screenshot failed: host did not write $source_path" >&2
	exit 1
fi

cp "$source_path" "$OUT_PATH"
echo "ios internal screenshot: $OUT_PATH"
