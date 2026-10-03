#!/bin/sh
# Publishes a release of every app in scripts/release/apps: the GitHub
# release v<version> with the DMG release.sh built for each, creating the
# release (and its tag, at the current commit) when it does not exist.
#
#   scripts/release/publish.sh 1.2.3
set -eu

version=${1:?usage: publish.sh <major.minor.patch>}
tag=v$version
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"

dmgs=""
names=""
for app in $(awk '!/^#/ && NF { print $1 }' scripts/release/apps); do
	product=$(awk -v app="$app" '$1 == app { print $2 }' scripts/release/apps)
	dmg="build/release/$app/$product-$version.dmg"
	[ -f "$dmg" ] || { echo "publish.sh: $dmg is not built (make release VERSION=$version)" >&2; exit 1; }
	dmgs="$dmgs $dmg"
	name=$(/usr/libexec/PlistBuddy -c "Print CFBundleDisplayName" "apps/$app/Info.plist")
	names="${names:+$names, }$name"
done

if gh release view "$tag" >/dev/null 2>&1; then
	gh release upload "$tag" $dmgs --clobber
else
	gh release create "$tag" $dmgs --title "$version: $names" --generate-notes --target "$(git rev-parse HEAD)"
fi
