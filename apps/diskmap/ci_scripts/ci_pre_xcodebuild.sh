#!/bin/sh
set -eu

# Xcode Cloud supplies CI_TAG for tag-triggered builds. Diskmap releases use
# tags like diskmap/1.2.3 so they never match Adventure Arena's release/ tags.
if [ -n "${CI_TAG:-}" ]; then
	cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/../../..}"
	python3 scripts/ipad/release_version.py --prefix diskmap "$CI_TAG" apps/diskmap/Info.plist
fi
