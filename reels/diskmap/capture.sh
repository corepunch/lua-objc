#!/bin/sh
# Captures the Diskmap pages the reel uses from the showcase disk
# (`--showcase`: the synthetic Mock HDD with presentable names). For each
# page and appearance it stores a window-only JPEG and the layout dump of the
# same window, pruned to the identified views, table rows and treemap cells
# the reel cuts pieces by.
#
#   reels/diskmap/capture.sh                 # every page, light and dark
#   reels/diskmap/capture.sh map-dark treemap-dark
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
out="$root/reels/diskmap/captures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$root"
mkdir -p "$out"

capture() { # name appearance lua-objc-arguments…
	name=$1 appearance=$2
	shift 2
	./lua-objc --screenshot="$tmp/$name-$appearance.png" --appearance="$appearance" --width=1440 --height=900 \
		apps/diskmap/init.lua --showcase "$@" >/dev/null
	./lua-objc --dump-layout="$tmp/$name-$appearance.layout.xml" --appearance="$appearance" --width=1440 --height=900 \
		apps/diskmap/init.lua --showcase "$@" >/dev/null
	./lua-objc modules/reel/tools/import.lua "$tmp/$name-$appearance.png" "$tmp/$name-$appearance.layout.xml" \
		"$out/$name-$appearance" "$appearance" 2880 1800
	echo "captures/$name-$appearance"
}

one() { # page-appearance
	page=${1%-*} appearance=${1##*-}
	case $page in
		treemap) capture treemap "$appearance" --page=map --map-style=rectangles ;;
		*) capture "$page" "$appearance" --page="$page" ;;
	esac
}

if [ $# -gt 0 ]; then
	for name in "$@"; do one "$name"; done
else
	for appearance in light dark; do
		for page in overview map largest files kinds cleanup developer xcode simulators updates guide treemap; do
			one "$page-$appearance"
		done
	done
fi
