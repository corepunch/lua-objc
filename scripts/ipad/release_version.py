#!/usr/bin/env python3
"""Set the TestFlight version from an Xcode Cloud release tag."""
import argparse
from pathlib import Path
import plistlib
import re


TAG_PATTERN = re.compile(r'release/([0-9]+\.[0-9]+\.[0-9]+)\Z')


def version_from_tag(tag: str) -> str:
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError('Expected a tag like release/1.2.3')
    return match[1]


def set_version(plist_path: Path, version: str) -> None:
    info = plistlib.loads(plist_path.read_bytes())
    info['CFBundleShortVersionString'] = version
    plist_path.write_bytes(plistlib.dumps(info, sort_keys=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('plist', type=Path)
    args = parser.parse_args()
    set_version(args.plist, version_from_tag(args.tag))


if __name__ == '__main__':
    main()
