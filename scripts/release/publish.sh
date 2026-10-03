#!/bin/sh
# Attaches the DMG release.sh built for a tag to the GitHub release named
# after it, creating the release (and the tag, at the current commit) when
# it does not exist.
#
#   scripts/release/publish.sh dnb/1.2.3
set -eu

tag=${1:?usage: publish.sh <app>/<version>}
app=${tag%%/*}
version=${tag#*/}
root=$(cd "$(dirname "$0")/../.." && pwd)
dmg=$(ls "$root/build/release/$app/"*"-$version.dmg")
name=$(/usr/libexec/PlistBuddy -c "Print CFBundleDisplayName" "$root/apps/$app/Info.plist")

if gh release view "$tag" >/dev/null 2>&1; then
	gh release upload "$tag" "$dmg" --clobber
else
	gh release create "$tag" "$dmg" --title "$name $version" --generate-notes \
		--target "$(git -C "$root" rev-parse HEAD)"
fi
