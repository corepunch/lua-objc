#!/bin/sh
set -eu

case_id=${CASE:-}
if [ -z "$case_id" ]; then
	echo "usage: make parity-case CASE=<fixture-id>" >&2
	exit 2
fi

case "$case_id" in
	text.single.default|button.standard.action-counter|surface.background-rounded|grid.two-by-two|text.long-ellipsis-italic|image.system-icon|padding.vertical-edges|container.section-groupbox) width=320 ;;
	stack.h.spacing.default-text-spacer) width=480 ;;
	*)
		echo "unknown parity case: $case_id" >&2
		exit 2
		;;
esac

root="build/parity/macos/$case_id"
height=120
if [ "$case_id" = "surface.background-rounded" ] || [ "$case_id" = "container.section-groupbox" ]; then height=160; fi
mkdir -p "$root"

LUA_OBJC_PARITY_CASE="$case_id" ./lua-objc \
	--width="$width" --height="$height" \
	--internal-screenshot="$root/candidate.png" \
	examples/swiftui_parity/init.lua

if [ ! -s "$root/candidate.png" ]; then
	echo "parity capture failed: screenshot was not produced for $case_id" >&2
	exit 1
fi

LUA_OBJC_PARITY_CASE="$case_id" ./lua-objc \
	--width="$width" --height="$height" \
	--dump-layout="$root/candidate.xml" \
	examples/swiftui_parity/init.lua

if [ ! -s "$root/candidate.xml" ]; then
	echo "parity capture failed: layout dump was not produced for $case_id" >&2
	exit 1
fi

echo "parity macOS capture complete: $root"
