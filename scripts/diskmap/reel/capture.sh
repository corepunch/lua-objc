#!/bin/sh
# Captures the Diskmap pages the reel uses, in light and dark, from the
# showcase disk (`--showcase`: the synthetic Mock HDD with presentable names),
# and stores window-only JPEGs in captures/. Run through `make diskmap-reel-captures`.
set -eu

root=$(cd "$(dirname "$0")/../../.." && pwd)
out="$root/scripts/diskmap/reel/captures"
tool="$root/build/diskmap-reel"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$root"
mkdir -p "$out"

capture() { # name appearance lua-objc-arguments…
	name=$1 appearance=$2
	shift 2
	./lua-objc --screenshot="$tmp/$name-$appearance.png" --appearance="$appearance" --width=1440 --height=900 \
		apps/diskmap/init.lua --showcase "$@" >/dev/null
	"$tool" import "$tmp/$name-$appearance.png" "$out/$name-$appearance.jpg" "$appearance"
	echo "captures/$name-$appearance.jpg"
}

for appearance in light dark; do
	for page in overview map largest files kinds cleanup developer xcode simulators updates guide; do
		capture "$page" "$appearance" --page="$page"
	done
	capture treemap "$appearance" --page=map --map-style=rectangles
done
