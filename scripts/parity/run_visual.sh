#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
platform=${PLATFORM:-macos}
device=${DEVICE:-booted}

case "$platform" in
	macos|ios) ;;
	*) echo "usage: PLATFORM=macos|ios DEVICE=booted make parity-visual" >&2; exit 2 ;;
esac

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
	export DEVELOPER_DIR
fi

mkdir -p "$repo_root/build/parity/runs"
run_root=$(mktemp -d "$repo_root/build/parity/runs/visual.XXXXXX")
spec="$run_root/cases.json"
reference="$run_root/reference"
candidate="$run_root/candidate"
report="$run_root/comparison.json"

make -C "$repo_root" parity-image-diff
if [ -n "${SPEC:-}" ]; then
	case "$SPEC" in
		/*) spec=$SPEC ;;
		*) spec="$repo_root/$SPEC" ;;
	esac
	if [ ! -s "$spec" ]; then
		echo "visual parity spec is missing or empty: $spec" >&2
		exit 2
	fi
else
	python3 "$repo_root/scripts/parity/batch.py" generate --out "$spec"
fi

if [ "$platform" = "macos" ]; then
	make -C "$repo_root" all
	"$repo_root/scripts/parity/batch_reference_build.sh" --macos
	python3 "$repo_root/scripts/parity/batch.py" capture --engine reference --screenshots \
		--spec "$spec" --out "$reference"
	python3 "$repo_root/scripts/parity/batch.py" capture --engine candidate --screenshots \
		--spec "$spec" --out "$candidate"
else
	make -C "$repo_root" ios-host ios-packager
	"$repo_root/scripts/parity/batch_reference_build.sh" --ios
	xcrun simctl install "$device" "$repo_root/build/ios/LuaRuntime.app"
	xcrun simctl install "$device" "$repo_root/build/parity/batch/SwiftUIBatchReference-iOS.app"
	python3 "$repo_root/scripts/parity/batch.py" capture --platform ios --device "$device" \
		--engine reference --screenshots --spec "$spec" --out "$reference"
	python3 "$repo_root/scripts/parity/batch.py" capture --platform ios --device "$device" \
		--engine candidate --screenshots --spec "$spec" --out "$candidate"
fi

set +e
python3 "$repo_root/scripts/parity/batch.py" compare --visual \
	--spec "$spec" --reference "$reference" --candidate "$candidate" --out "$report"
status=$?
set -e

echo "visual parity artifacts: $run_root"
echo "comparison report: $report"
exit "$status"
