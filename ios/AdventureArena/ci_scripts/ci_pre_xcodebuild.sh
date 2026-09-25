#!/bin/sh
set -eu

# Xcode Cloud supplies CI_TAG for tag-triggered builds. Keep the plist change
# in the same action that runs xcodebuild so archive metadata matches the tag.
if [ -n "${CI_TAG:-}" ]; then
	cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/../../..}"
	python3 scripts/ipad/release_version.py "$CI_TAG" ios/AdventureArena/Info.plist
fi
