#!/bin/sh
set -eu

case_id=${CASE:-}
if [ -z "$case_id" ]; then
	echo "usage: CASE=<manifest-id> scripts/parity/reference_run.sh [--screenshot path] [--activate]" >&2
	exit 2
fi

case "$case_id" in
	text.single.default|stack.h.spacing.default-text-spacer|button.standard.action-counter|surface.background-rounded|grid.two-by-two|text.long-ellipsis-italic|image.system-icon|padding.vertical-edges) ;;
	*) echo "unknown parity case: $case_id" >&2; exit 2 ;;
esac

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
build_dir=${REFERENCE_BUILD_DIR:-"$repo_root/build/parity/reference"}
binary="$build_dir/SwiftUIParityReference"
app="$build_dir/SwiftUIParityReference.app"
ready_file=${REFERENCE_READY_FILE:-"$build_dir/$case_id.ready.json"}
generation=${REFERENCE_GENERATION:-"$(date +%s)-$$"}
duration=${REFERENCE_DURATION:-3}
activate=0
screenshot=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		--activate) activate=1 ;;
		--screenshot) shift; [ "$#" -gt 0 ] || { echo "missing screenshot path" >&2; exit 2; }; screenshot=$1 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

if [ ! -x "$app/Contents/MacOS/SwiftUIParityReference" ]; then
	"$repo_root/scripts/parity/reference_build.sh"
fi
rm -f "$ready_file"
command_args="--case $case_id --ready-file $ready_file --generation $generation"
if [ "$activate" -eq 1 ]; then command_args="$command_args --activate"; fi

open -n "$app" --args $command_args >"$build_dir/$case_id.stdout.log" 2>"$build_dir/$case_id.stderr.log" &
launcher_pid=$!
trap 'kill "$launcher_pid" 2>/dev/null || true' EXIT INT TERM

i=0
while [ ! -s "$ready_file" ] && [ "$i" -lt 50 ]; do
	i=$((i + 1))
	sleep 0.1
done
if [ ! -s "$ready_file" ]; then
	echo "reference run failed: readiness file was not produced" >&2
	sed -n '1,80p' "$build_dir/$case_id.stderr.log" >&2 || true
	exit 1
fi

if [ -n "$screenshot" ]; then
	if ! command -v screencapture >/dev/null 2>&1; then
		echo "reference run blocked: screencapture is unavailable" >&2
		exit 2
	fi
	if [ -z "${REFERENCE_WINDOW_ID:-}" ]; then
		echo "reference run blocked: set REFERENCE_WINDOW_ID for non-interactive capture" >&2
		exit 2
	fi
	screencapture -x -l "$REFERENCE_WINDOW_ID" "$screenshot" || {
		echo "reference run failed: window screenshot was not captured" >&2
		exit 1
	}
	[ -s "$screenshot" ] || { echo "reference run failed: empty screenshot" >&2; exit 1; }
fi

sleep "$duration"
echo "reference host ready: $ready_file"
cat "$ready_file"
